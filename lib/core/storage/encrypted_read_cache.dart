import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';

enum ReadSyncPhase { pending, online, offline, failed }

typedef ReadSyncStatus = ({ReadSyncPhase phase, DateTime? verifiedAt});

/// Provenance belongs to this read, independently of local persistence status.
typedef ProductReadResult = ({
  Map<String, dynamic>? product,
  bool serverVerified,
});

/// Session-scoped read cache. Tokens and permissions are never persisted.
class EncryptedReadCache {
  new(this.database, {required String sessionSecret, DateTime Function()? now})
    : _identity = sessionSecret,
      _now = now ?? DateTime.now;

  final ReadCacheDatabase database;
  final String _identity;
  final DateTime Function() _now;
  final _cipher = AesGcm.with256bits();
  final _events = StreamController<int>.broadcast();
  final _recovery = StreamController<int>.broadcast();
  final _statuses = <String, ReadSyncStatus>{};
  final _pending = <String, Future<ProductReadResult>>{};
  final _unavailable = <String>{};
  int _revision = 0;
  int _changeSequence = 0;
  int _recoverySequence = 0;
  bool _closed = false;
  bool offline = false;
  bool _probe = true;
  bool _writing = false;
  Future<SecretKey>? _key;
  Future<String>? _owner;

  void retryRead() => _probe = true;

  Stream<int> get changes => _events.stream;
  Stream<int> get recovery => _recovery.stream;
  ReadSyncStatus status(String barcode) =>
      _statuses[barcode] ??
      (
        phase: offline ? ReadSyncPhase.offline : ReadSyncPhase.online,
        verifiedAt: null,
      );

  Future<SecretKey> get key => _key ??= Sha256()
      .hash(utf8.encode('orangeone.product-cache.v1:$_identity'))
      .then((hash) => SecretKey(hash.bytes));
  Future<String> get owner => _owner ??= _hash(_identity);
  Future<String> _hash(String value) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(value))).bytes);

  void _set(String barcode, ReadSyncPhase phase, [DateTime? time]) {
    if (_closed) return;
    _statuses[barcode] = (
      phase: phase,
      verifiedAt: time ?? _statuses[barcode]?.verifiedAt,
    );
    _events.add(++_changeSequence);
  }

  /// Interface connectivity is a hint; server reads confirm online status.
  void connectionChanged({required bool connected}) {
    if (_closed) return;
    if (!connected) {
      offline = true;
      _probe = false;
      for (final code in _statuses.keys.toList()) {
        _set(code, ReadSyncPhase.offline);
      }
      _events.add(++_changeSequence);
    } else if (offline) {
      // Keep writes disabled until an authoritative read succeeds.
      _probe = true;
      _recovery.add(++_recoverySequence);
    }
  }

  Future<Map<String, dynamic>?> load(
    String barcode,
    Future<Map<String, dynamic>?> Function() fetch,
  ) async => (await loadResult(barcode, fetch)).product;

  Future<ProductReadResult> loadResult(
    String barcode,
    Future<Map<String, dynamic>?> Function() fetch,
  ) async =>
      await (_pending[barcode] ??= _load(barcode, fetch).whenComplete(() {
        _pending.removeWhere((key, value) => key == barcode);
      }));

  Future<ProductReadResult> _load(
    String barcode,
    Future<Map<String, dynamic>?> Function() fetch,
  ) async {
    if (_closed || _writing) throw cancelledOperation;
    if (offline && !_probe) {
      final cached = await read(barcode);
      if (cached != null) return (product: cached, serverVerified: false);
      throw const AppFailure(
        FailureKind.network,
        'No cached product is available. Reconnect to look it up.',
      );
    }
    _probe = false;
    final revision = _revision;
    _set(barcode, ReadSyncPhase.pending);
    try {
      final product = await fetch();
      if (_closed || revision != _revision) throw cancelledOperation;
      final time = _now().toUtc();
      // Only approved display fields; never cache capability or auth responses.
      final approved = product == null
          ? null
          : <String, dynamic>{
              for (final field in [
                'id',
                'name',
                'barcode',
                'price',
                'stock_quantity',
                'uom',
                'default_code',
              ])
                if (product.containsKey(field)) field: product[field],
            };
      if (approved != null && product?['taxes'] is List) {
        approved['taxes'] = (product!['taxes'] as List)
            .whereType<Map<String, dynamic>>()
            .map(
              (tax) => {
                for (final field in ['id', 'name', 'amount', 'amount_type'])
                  if (tax.containsKey(field)) field: tax[field],
              },
            )
            .toList();
      }
      try {
        if (approved == null) {
          await _remove(barcode);
        } else {
          final box = await _cipher.encrypt(
            utf8.encode(
              jsonEncode({'product': approved, 'at': time.toIso8601String()}),
            ),
            secretKey: await key,
            aad: utf8.encode(barcode),
          );
          if (!_closed && revision == _revision) {
            await database.customStatement(
              'INSERT OR REPLACE INTO product_reads VALUES (?, ?, ?)',
              [
                await owner,
                await _hash(barcode),
                base64Encode(box.concatenation()),
              ],
            );
            await database.customStatement(
              'DELETE FROM product_reads WHERE rowid NOT IN '
              '(SELECT rowid FROM product_reads ORDER BY rowid DESC LIMIT 500)',
            );
          }
        }
      } on Exception {
        // A cache failure must not hide a valid server response.
        if (_closed || revision != _revision) throw cancelledOperation;
        // A failed replacement/removal must not expose the older snapshot.
        offline = false;
        _unavailable.add(barcode);
        _set(barcode, ReadSyncPhase.failed, time);
        return (product: product, serverVerified: true);
      }
      if (_closed || revision != _revision) throw cancelledOperation;
      offline = false;
      _unavailable.remove(barcode);
      _set(barcode, ReadSyncPhase.online, time);
      return (product: product, serverVerified: true);
    } on AppFailure catch (failure) {
      if (_closed || revision != _revision) throw cancelledOperation;
      if (failure.kind != FailureKind.network &&
          failure.kind != FailureKind.timeout) {
        try {
          await _remove(barcode);
        } on Exception {
          // Preserve authentication rejection even when cache cleanup fails.
          // Session key removal still makes its encrypted payload inaccessible.
        }
        _set(barcode, ReadSyncPhase.failed);
        rethrow;
      }
      connectionChanged(connected: false);
      _set(barcode, ReadSyncPhase.offline);
      final cached = await read(barcode);
      if (cached == null) rethrow;
      return (product: cached, serverVerified: false);
    }
  }

  Future<void> _remove(String barcode) async {
    await database.customStatement(
      'DELETE FROM product_reads WHERE owner = ? AND code = ?',
      [await owner, await _hash(barcode)],
    );
  }

  Future<Map<String, dynamic>?> read(String barcode) async {
    if (_closed || _unavailable.contains(barcode)) return null;
    try {
      final row = await database
          .customSelect(
            'SELECT payload FROM product_reads WHERE owner = ? AND code = ?',
            variables: [Variable(await owner), Variable(await _hash(barcode))],
          )
          .getSingleOrNull();
      if (row == null) return null;
      final decoded = await _cipher.decrypt(
        SecretBox.fromConcatenation(
          base64Decode(row.read<String>('payload')),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: await key,
        aad: utf8.encode(barcode),
      );
      final value = jsonDecode(utf8.decode(decoded));
      if (value is! Map<String, dynamic> ||
          value['at'] is! String ||
          value['product'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid cached product.');
      }
      if (_closed || _unavailable.contains(barcode)) return null;
      final time = DateTime.parse(value['at'] as String);
      if (_now().toUtc().difference(time) > const Duration(days: 1)) {
        return null;
      }
      _set(barcode, ReadSyncPhase.offline, time);
      return value['product'] as Map<String, dynamic>;
    } on Object {
      _set(barcode, ReadSyncPhase.failed);
      throw const AppFailure(
        FailureKind.storage,
        'Cached product data is unavailable. '
        'Reconnect and refresh.',
      );
    }
  }

  Future<T> write<T>(Future<T> Function() operation) async {
    if (_closed || offline || _writing) {
      throw const AppFailure(
        FailureKind.network,
        'Offline changes are disabled. '
        'Reconnect and refresh first.',
      );
    }
    _writing = true;
    _revision++;
    try {
      // Invalidate before uncertain writes; never reuse pre-write data.
      try {
        await database.customStatement(
          'DELETE FROM product_reads WHERE owner = ?',
          [await owner],
        );
      } on Exception {
        throw const AppFailure(
          FailureKind.storage,
          'Unable to invalidate cached data. No changes were sent. '
          'Resolve the storage problem and retry.',
        );
      }
      return await operation();
    } on AppFailure catch (failure) {
      if (failure.kind == FailureKind.network ||
          failure.kind == FailureKind.timeout) {
        connectionChanged(connected: false);
      }
      rethrow;
    } finally {
      _writing = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _revision++;
    try {
      await database.customStatement(
        'DELETE FROM product_reads WHERE owner = ?',
        [await owner],
      );
    } finally {
      await _events.close();
      await _recovery.close();
    }
  }
}
