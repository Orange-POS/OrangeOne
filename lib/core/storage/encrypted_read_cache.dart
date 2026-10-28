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

/// Change-feed position stored per session (`GET /products/changes`).
typedef CacheSyncState = ({String since});

/// Session-scoped read cache (schema 2: Mobile API v2 product reads).
/// Tokens, permissions, versions and pending writes are never persisted.
class EncryptedReadCache {
  new(this.database, {required String sessionSecret, DateTime Function()? now})
    : _identity = sessionSecret,
      _now = now ?? DateTime.now;

  /// Encrypted envelope schema; other envelopes are discarded as misses.
  static const schema = 2;

  /// Approved display fields of a v2 product read record. Write-only data
  /// (`version`, `permissions`, adjustability, locations) is never stored.
  static const _fields = [
    'id',
    'name',
    'barcode',
    'price',
    'currency',
    'stock_quantity',
    'stock_tracked',
    'uom',
    'default_code',
    'description',
    'updated_at',
  ];

  /// Reserved code input for the sync position; barcodes are printable.
  static const _syncCode = '\u0000sync';

  /// Reserved code input for the recently scanned products of the session.
  static const _recentCode = '\u0000recent';

  /// Most recently scanned products that are kept.
  static const recentScanLimit = 5;

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
  Future<void>? _persistence;

  // Order snapshot changes and purges, never backend mutations.
  Future<T> _persist<T>(Future<T> Function() operation) {
    final previous = _persistence;
    final completed = Completer<void>();
    _persistence = completed.future;
    return () async {
      if (previous != null) await previous;
      try {
        return await operation();
      } finally {
        completed.complete();
      }
    }();
  }

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
      .hash(utf8.encode('orangeone.product-cache.v$schema:$_identity'))
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
      final approved = product == null ? null : _approved(product);
      try {
        if (approved == null) {
          await _remove(barcode, revision: revision);
        } else {
          await _store(barcode, approved, time, revision: revision);
        }
      } on Exception {
        // A cache failure must not hide a valid server response.
        if (_closed || revision != _revision) throw cancelledOperation;
        // Block local fallback while removing the old snapshot durably.
        _unavailable.add(barcode);
        try {
          await _remove(barcode, revision: revision);
        } on Exception {
          // Keep the instance-local guard if durable cleanup also fails.
        }
        if (_closed || revision != _revision) throw cancelledOperation;
        offline = false;
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
          await _remove(barcode, revision: revision);
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

  Future<void> _remove(String barcode, {required int revision}) async {
    final identity = await owner;
    final code = await _hash(barcode);
    await _persist(() async {
      if (_closed || revision != _revision) throw cancelledOperation;
      await database.customStatement(
        'DELETE FROM product_reads WHERE owner = ? AND code = ?',
        [identity, code],
      );
    });
  }

  Future<void> _purge({bool keepRecents = false}) async {
    final identity = await owner;
    final recent = await _hash(_recentCode);
    await _persist(
      () => keepRecents
          ? database.customStatement(
              'DELETE FROM product_reads WHERE owner = ? AND code != ?',
              [identity, recent],
            )
          : database.customStatement(
              'DELETE FROM product_reads WHERE owner = ?',
              [identity],
            ),
    );
  }

  Future<Map<String, dynamic>?> read(String barcode) async {
    if (_closed || _unavailable.contains(barcode)) return null;
    try {
      final code = await _hash(barcode);
      final row = await database
          .customSelect(
            'SELECT payload FROM product_reads WHERE owner = ? AND code = ?',
            variables: [Variable(await owner), Variable(code)],
          )
          .getSingleOrNull();
      if (row == null) return null;
      final value = await _open(row.read<String>('payload'), code);
      if (value == null) {
        // An older schema: never an error, just not available offline.
        await _remove(barcode, revision: _revision);
        return null;
      }
      final product = value['product'];
      if (value['at'] is! String ||
          product is! Map<String, dynamic> ||
          product['barcode'] != barcode) {
        throw const FormatException('Invalid cached product.');
      }
      if (_closed || _unavailable.contains(barcode)) return null;
      final time = DateTime.parse(value['at'] as String);
      if (_now().toUtc().difference(time) > const Duration(days: 1)) {
        return null;
      }
      _set(barcode, ReadSyncPhase.offline, time);
      return product;
    } on Object {
      _set(barcode, ReadSyncPhase.failed);
      throw const AppFailure(
        FailureKind.storage,
        'Cached product data is unavailable. '
        'Reconnect and refresh.',
      );
    }
  }

  /// Encrypts [body] for one row. The row code is authenticated (AAD), so a
  /// payload cannot be moved to another barcode or owner.
  Future<String> _seal(String code, Map<String, dynamic> body) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode({'v': schema, ...body})),
      secretKey: await key,
      aad: utf8.encode('v$schema|$code'),
    );
    return base64Encode(box.concatenation());
  }

  /// Decrypts a row; null for another schema. Malformed or tampered rows
  /// throw and are reported as storage failures by callers.
  Future<Map<String, dynamic>?> _open(String payload, String code) async {
    final decoded = await _cipher.decrypt(
      SecretBox.fromConcatenation(
        base64Decode(payload),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: await key,
      aad: utf8.encode('v$schema|$code'),
    );
    final value = jsonDecode(utf8.decode(decoded));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid cache envelope.');
    }
    return value['v'] == schema ? value : null;
  }

  static Map<String, dynamic> _approved(Map<String, dynamic> product) {
    final approved = <String, dynamic>{
      for (final field in _fields)
        if (product.containsKey(field)) field: product[field],
    };
    final category = product['category'];
    if (category is Map<String, dynamic>) {
      approved['category'] = {
        for (final field in ['id', 'name'])
          if (category.containsKey(field)) field: category[field],
      };
    }
    if (product['taxes'] is List) {
      approved['taxes'] = (product['taxes'] as List)
          .whereType<Map<String, dynamic>>()
          .map(
            (tax) => {
              for (final field in ['id', 'name', 'amount', 'amount_type'])
                if (tax.containsKey(field)) field: tax[field],
            },
          )
          .toList();
    }
    return approved;
  }

  /// Persists an approved snapshot unless a mutation or logout intervened.
  Future<void> _store(
    String barcode,
    Map<String, dynamic> approved,
    DateTime time, {
    required int revision,
  }) async {
    // Finish async preparation before the generation check at dispatch.
    final identity = await owner;
    final code = await _hash(barcode);
    final payload = await _seal(code, {
      'product': approved,
      'at': time.toIso8601String(),
    });
    await _persist(() async {
      if (_closed || revision != _revision) throw cancelledOperation;
      await database.customStatement(
        'INSERT OR REPLACE INTO product_reads VALUES (?, ?, ?)',
        [identity, code, payload],
      );
      await database.customStatement(
        'DELETE FROM product_reads WHERE rowid NOT IN '
        '(SELECT rowid FROM product_reads ORDER BY rowid DESC LIMIT 500)',
      );
    });
  }

  /// Stores a product the server just confirmed (for example a write
  /// acknowledgement). Failures keep the server result valid: the snapshot
  /// is removed instead, so stale data is never served.
  Future<void> put(String barcode, Map<String, dynamic> product) async {
    if (_closed || _writing) return;
    final revision = _revision;
    final time = _now().toUtc();
    try {
      await _store(barcode, _approved(product), time, revision: revision);
      _unavailable.remove(barcode);
      _set(barcode, ReadSyncPhase.online, time);
      await _syncRecents(changed: [product], removedIds: const []);
    } on Exception {
      if (_closed || revision != _revision) return;
      _unavailable.add(barcode);
      try {
        await _remove(barcode, revision: revision);
      } on Exception {
        // The instance-local guard still blocks the stale snapshot.
      }
      _set(barcode, ReadSyncPhase.failed, time);
    }
  }

  /// Change-feed position for this session: the stored `next_since`, or a
  /// start a little before the oldest cached snapshot. Null when nothing is
  /// cached, so there is nothing to synchronize.
  Future<CacheSyncState?> syncState() async {
    if (_closed) return null;
    final rows = await _rows();
    final sync = rows.remove(await _hash(_syncCode));
    DateTime? oldest;
    for (final value in rows.values) {
      final at = value == null ? null : DateTime.tryParse('${value['at']}');
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    if (oldest == null) return null;
    final since = sync?['since'];
    if (since is String && since.isNotEmpty) return (since: since);
    // Margin for device clock skew; the feed may then repeat products.
    final start = oldest.toUtc().subtract(const Duration(minutes: 5));
    // RFC 3339 in whole seconds, as the contract's examples use.
    return (since: '${start.toIso8601String().split('.').first}Z');
  }

  /// Applies one verified page of `GET /products/changes`.
  ///
  /// Only products already cached in this session are refreshed: a changed
  /// product replaces its snapshot unless the snapshot is newer
  /// (`updated_at`), a new barcode drops the old entry, and removed ids are
  /// deleted. The position is saved last, so an interrupted sync repeats the
  /// page. Mutations or logout during the page cancel it.
  Future<void> applyChanges({
    required List<Map<String, dynamic>> changed,
    required List<int> removedIds,
    required String nextSince,
  }) async {
    if (_closed || _writing) throw cancelledOperation;
    final revision = _revision;
    final syncCode = await _hash(_syncCode);
    final cached = <int, ({String code, Map<String, dynamic> product})>{};
    for (final MapEntry(key: code, :value) in (await _rows()).entries) {
      final product = value?['product'];
      if (code == syncCode || product is! Map<String, dynamic>) continue;
      if (product['id'] case final int id) {
        cached[id] = (code: code, product: product);
      }
    }
    final time = _now().toUtc();
    final touched = <String>{};
    for (final id in removedIds) {
      final entry = cached.remove(id);
      if (entry != null) await _removeCode(entry.code, revision: revision);
    }
    for (final product in changed) {
      final entry = cached[product['id']];
      if (entry == null) continue;
      final barcode = product['barcode'];
      final previous = entry.product['barcode'];
      if (barcode != previous) {
        await _removeCode(entry.code, revision: revision);
        if (previous is String) _statuses.remove(previous);
      }
      if (barcode is! String) continue;
      final known = DateTime.tryParse('${entry.product['updated_at']}');
      final incoming = DateTime.tryParse('${product['updated_at']}');
      if (barcode == previous &&
          known != null &&
          (incoming == null || incoming.isBefore(known))) {
        continue; // Never let an older feed entry replace newer data.
      }
      await _store(barcode, _approved(product), time, revision: revision);
      _unavailable.remove(barcode);
      touched.add(barcode);
    }
    await _syncRecents(
      changed: changed,
      removedIds: removedIds,
      revision: revision,
    );
    final identity = await owner;
    final payload = await _seal(syncCode, {'since': nextSince});
    await _persist(() async {
      if (_closed || revision != _revision) throw cancelledOperation;
      await database.customStatement(
        'INSERT OR REPLACE INTO product_reads VALUES (?, ?, ?)',
        [identity, syncCode, payload],
      );
    });
    for (final barcode in touched) {
      if (_statuses[barcode] case final status?) {
        _statuses[barcode] = (phase: status.phase, verifiedAt: time);
      }
    }
    if (!_closed) _events.add(++_changeSequence);
  }

  /// Drops every snapshot and the sync position of this session, for
  /// example after an expired feed position or lost read permission.
  Future<void> resetSync() async {
    if (_closed) return;
    // In-flight reads still store fresh, authorized server responses.
    await _purge();
    if (!_closed) _events.add(++_changeSequence);
  }

  /// Decrypted rows of this owner by code; null for discarded rows. Rows of
  /// another schema or that fail authentication are deleted.
  Future<Map<String, Map<String, dynamic>?>> _rows() async {
    final identity = await owner;
    final rows = await database
        .customSelect(
          'SELECT code, payload FROM product_reads WHERE owner = ?',
          variables: [Variable(identity)],
        )
        .get();
    final result = <String, Map<String, dynamic>?>{};
    for (final row in rows) {
      final code = row.read<String>('code');
      Map<String, dynamic>? value;
      try {
        value = await _open(row.read<String>('payload'), code);
      } on Object {
        value = null;
      }
      if (value == null) {
        await _removeCode(code, revision: _revision);
      }
      result[code] = value;
    }
    return result;
  }

  Future<void> _removeCode(String code, {required int revision}) async {
    final identity = await owner;
    await _persist(() async {
      if (_closed || revision != _revision) throw cancelledOperation;
      await database.customStatement(
        'DELETE FROM product_reads WHERE owner = ? AND code = ?',
        [identity, code],
      );
    });
  }

  /// Recently scanned products of this session, newest first, as display
  /// records (`id`, `name`, `barcode`, `price`, `stock_quantity`, `uom`,
  /// `category` name).
  /// They are encrypted like snapshots, belong to this session only and are
  /// deleted with it. Malformed or tampered data is a safe storage failure.
  Future<List<Map<String, dynamic>>> readRecents() async {
    if (_closed) return const [];
    try {
      final code = await _hash(_recentCode);
      final row = await database
          .customSelect(
            'SELECT payload FROM product_reads WHERE owner = ? AND code = ?',
            variables: [Variable(await owner), Variable(code)],
          )
          .getSingleOrNull();
      if (row == null) return const [];
      final value = await _open(row.read<String>('payload'), code);
      final items = value?['items'];
      return items is List ? _recentItems(items) : const [];
    } on Object {
      throw const AppFailure(
        FailureKind.storage,
        'Recent scans are unavailable on this device.',
      );
    }
  }

  /// Puts [product] (a product read record) first, replacing an earlier
  /// entry of the same product, and keeps at most [recentScanLimit].
  Future<void> recordRecent(Map<String, dynamic> product) async {
    final item = _recentItem(product);
    if (_closed || _writing || item == null) return;
    await _changeRecents(
      _revision,
      (items) => [
        item,
        ...items.where(
          (other) =>
              other['id'] != item['id'] && other['barcode'] != item['barcode'],
        ),
      ].take(recentScanLimit).toList(),
    );
  }

  /// Refreshes entries of [changed] products and drops [removedIds].
  Future<void> _syncRecents({
    required List<Map<String, dynamic>> changed,
    required List<int> removedIds,
    int? revision,
  }) async {
    try {
      await _changeRecents(revision ?? _revision, (items) {
        final updated = <Map<String, dynamic>>[];
        for (final item in items) {
          if (removedIds.contains(item['id'])) continue;
          final record = changed
              .where((c) => c['id'] == item['id'])
              .firstOrNull;
          final next = record == null ? item : _recentItem(record);
          if (next != null &&
              !updated.any((other) => other['barcode'] == next['barcode'])) {
            updated.add(next);
          }
        }
        return updated;
      });
    } on Exception {
      // The recent list is best effort and never blocks a refresh.
    }
  }

  Future<void> _changeRecents(
    int revision,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> items)
    change,
  ) async {
    final identity = await owner;
    final code = await _hash(_recentCode);
    await _persist(() async {
      if (_closed || revision != _revision) throw cancelledOperation;
      var current = <Map<String, dynamic>>[];
      try {
        current = await readRecents();
      } on AppFailure {
        // A damaged list is replaced by the next change.
      }
      final next = change(current);
      if (jsonEncode(next) == jsonEncode(current)) return;
      final payload = await _seal(code, {'items': next});
      await database.customStatement(
        'INSERT OR REPLACE INTO product_reads VALUES (?, ?, ?)',
        [identity, code, payload],
      );
    });
  }

  static List<Map<String, dynamic>> _recentItems(List<Object?> raw) {
    final items = <Map<String, dynamic>>[];
    for (final value in raw) {
      final item = value is Map<String, dynamic> ? _recentItem(value) : null;
      if (item != null && items.length < recentScanLimit) items.add(item);
    }
    return items;
  }

  /// Only what the recent card shows, plus the id used to keep it current.
  static Map<String, dynamic>? _recentItem(Map<String, dynamic> product) {
    final id = product['id'];
    final barcode = product['barcode'];
    final name = product['name'];
    final price = product['price'];
    final stock = product['stock_quantity'];
    final unit = product['uom'];
    // A product record has `{id, name}`; a stored entry just the name.
    final rawCategory = product['category'];
    final category = rawCategory is Map<String, dynamic>
        ? rawCategory['name']
        : rawCategory;
    if (id is! int ||
        id <= 0 ||
        barcode is! String ||
        barcode.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        price is! num ||
        !price.isFinite ||
        (stock != null && (stock is! num || !stock.isFinite))) {
      return null;
    }
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'price': price.toDouble(),
      'stock_quantity': (stock as num?)?.toDouble(),
      'uom': unit is String ? unit : '',
      'category': category is String && category.trim().isNotEmpty
          ? category.trim()
          : null,
    };
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
      // The recent list holds display fields only and is refreshed by `put`.
      try {
        await _purge(keepRecents: true);
      } on Exception {
        throw const AppFailure(
          FailureKind.storage,
          'Unable to invalidate cached data. No changes were sent. '
          'Resolve the storage problem and retry.',
        );
      }
      if (_closed) throw cancelledOperation;
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
      await _purge();
    } finally {
      await _events.close();
      await _recovery.close();
    }
  }
}
