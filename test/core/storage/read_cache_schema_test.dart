import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';

/// The schema shipped before Mobile API v2 (same table, version 1).
class _V1Database extends ReadCacheDatabase {
  new(super.executor);
  @override
  int get schemaVersion => 1;
}

Map<String, dynamic> _record({
  int id = 7,
  String barcode = '4006381333931',
  String name = 'Cached product',
  double price = 10,
  String updatedAt = '2026-10-20T08:00:00Z',
}) => {
  'id': id,
  'name': name,
  'barcode': barcode,
  'price': price,
  'currency': 'CHF',
  'stock_quantity': 4.0,
  'stock_tracked': true,
  'uom': 'Units',
  'default_code': 'REF',
  'description': 'Subtitle',
  'updated_at': updatedAt,
  'category': {'id': 4, 'name': 'Spices', 'complete_name': 'All / Spices'},
  'taxes': [
    {'id': 7, 'name': 'VAT', 'amount': 8.1, 'amount_type': 'percent'},
  ],
  // Never cached:
  'version': '3',
  'permissions': {'product_update_price': true},
  'stock_adjustable': true,
  'stock_location_id': 8,
  'uom_rounding': '0.01',
};

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  late DateTime now;
  setUp(() {
    database = ReadCacheDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 20, 9);
    cache = EncryptedReadCache(
      database,
      sessionSecret: 'synthetic-session',
      now: () => now,
    );
  });
  tearDown(() async {
    await cache.close();
    await database.close();
  });

  Future<int> rows() async =>
      (await database
              .customSelect('SELECT COUNT(*) AS c FROM product_reads')
              .getSingle())
          .read<int>('c');

  test(
    'v2 display fields are restored; write-only data is not cached',
    () async {
      await cache.load('4006381333931', () async => _record());
      final cached = await cache.read('4006381333931');
      expect(cached, {
        'id': 7,
        'name': 'Cached product',
        'barcode': '4006381333931',
        'price': 10.0,
        'currency': 'CHF',
        'stock_quantity': 4.0,
        'stock_tracked': true,
        'uom': 'Units',
        'default_code': 'REF',
        'description': 'Subtitle',
        'updated_at': '2026-10-20T08:00:00Z',
        'category': {'id': 4, 'name': 'Spices'},
        'taxes': [
          {'id': 7, 'name': 'VAT', 'amount': 8.1, 'amount_type': 'percent'},
        ],
      });
    },
  );

  test('upgrading a v1 database discards its snapshots', () async {
    // A separate file next to the in-memory database of setUp.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );
    final directory = await Directory.systemTemp.createTemp('read-cache');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/product_reads.sqlite');
    final v1 = _V1Database(NativeDatabase(file));
    await v1.customStatement('INSERT INTO product_reads VALUES (?, ?, ?)', [
      'owner',
      'code',
      'v1-payload',
    ]);
    await v1.close();

    final v2 = ReadCacheDatabase(NativeDatabase(file));
    addTearDown(v2.close);
    final count = await v2
        .customSelect('SELECT COUNT(*) AS c FROM product_reads')
        .getSingle();
    expect(count.read<int>('c'), 0);
    expect(v2.schemaVersion, EncryptedReadCache.schema);
  });

  test('an older envelope is a cache miss, never an error', () async {
    await cache.load('4006381333931', () async => _record());
    // Re-encrypt the row as a v1 envelope under the same key and binding.
    final row = await database
        .customSelect('SELECT code FROM product_reads')
        .getSingle();
    final code = row.read<String>('code');
    final key = SecretKey(
      (await Sha256().hash(
        utf8.encode('orangeone.product-cache.v2:synthetic-session'),
      )).bytes,
    );
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'product': {'id': 7, 'barcode': '4006381333931'},
          'at': now.toIso8601String(),
        }),
      ),
      secretKey: key,
      aad: utf8.encode('v2|$code'),
    );
    await database.customStatement('UPDATE product_reads SET payload = ?', [
      base64Encode(box.concatenation()),
    ]);

    expect(await cache.read('4006381333931'), isNull);
    expect(await rows(), 0);
  });

  test('a payload moved to another barcode fails authentication', () async {
    await cache.load('4006381333931', () async => _record());
    await cache.load(
      '4006381333948',
      () async => _record(id: 8, barcode: '4006381333948'),
    );
    final payloads = await database
        .customSelect('SELECT code, payload FROM product_reads ORDER BY code')
        .get();
    await database.customStatement(
      'UPDATE product_reads SET payload = ? WHERE code = ?',
      [
        payloads.first.read<String>('payload'),
        payloads.last.read<String>('code'),
      ],
    );
    final corrupted = [
      for (final barcode in ['4006381333931', '4006381333948'])
        await cache.read(barcode).then((_) => false, onError: (_) => true),
    ];
    expect(corrupted, contains(true));
  });

  test('put stores a confirmed product and reports it online', () async {
    await cache.put('4006381333931', _record(price: 12));
    expect((await cache.read('4006381333931'))?['price'], 12);
    expect(cache.status('4006381333931').phase, ReadSyncPhase.offline);
  });

  group('change feed', () {
    setUp(() async {
      await cache.load('4006381333931', () async => _record());
      await cache.load(
        '4006381333948',
        () async => _record(id: 8, barcode: '4006381333948', name: 'Second'),
      );
    });

    test('starts just before the oldest snapshot, then resumes', () async {
      expect((await cache.syncState())?.since, '2026-10-20T08:55:00Z');
      await cache.applyChanges(
        changed: const [],
        removedIds: const [],
        nextSince: 'opaque-1',
      );
      expect((await cache.syncState())?.since, 'opaque-1');
    });

    test('nothing cached means nothing to synchronize', () async {
      await cache.resetSync();
      expect(await cache.syncState(), isNull);
      expect(await rows(), 0);
    });

    test('refreshes, removes and re-keys only cached products', () async {
      await cache.applyChanges(
        changed: [
          _record(price: 11, updatedAt: '2026-10-20T08:30:00Z'),
          _record(id: 8, barcode: 'NEW-8', updatedAt: '2026-10-20T08:30:00Z'),
          _record(id: 99, barcode: 'NOT-CACHED'),
        ],
        removedIds: const [12345],
        nextSince: 'opaque-1',
      );
      expect((await cache.read('4006381333931'))?['price'], 11);
      expect(await cache.read('4006381333948'), isNull);
      expect((await cache.read('NEW-8'))?['id'], 8);
      expect(await cache.read('NOT-CACHED'), isNull);

      await cache.applyChanges(
        changed: const [],
        removedIds: const [7],
        nextSince: 'opaque-2',
      );
      expect(await cache.read('4006381333931'), isNull);
    });

    test('an older feed entry never replaces newer data', () async {
      await cache.load(
        '4006381333931',
        () async => _record(price: 20, updatedAt: '2026-10-20T08:45:00Z'),
      );
      await cache.applyChanges(
        changed: [_record(price: 11, updatedAt: '2026-10-20T08:30:00Z')],
        removedIds: const [],
        nextSince: 'opaque-1',
      );
      expect((await cache.read('4006381333931'))?['price'], 20);
    });

    test('a mutation during a page cancels it without changes', () async {
      final pending = cache.applyChanges(
        changed: [_record(price: 11, updatedAt: '2026-10-20T08:30:00Z')],
        removedIds: const [8],
        nextSince: 'opaque-1',
      );
      final write = cache.write(() async {});
      await expectLater(pending, throwsA(same(cancelledOperation)));
      await write;
      expect(await cache.syncState(), isNull, reason: 'write purged all');
    });

    test('corrupt rows are dropped instead of breaking the sync', () async {
      await database.customStatement(
        "UPDATE product_reads SET payload = 'broken'",
      );
      expect(await cache.syncState(), isNull);
      expect(await rows(), 0);
    });
  });

  test('another session cannot see or sync this session data', () async {
    await cache.load('4006381333931', () async => _record());
    final other = EncryptedReadCache(database, sessionSecret: 'other');
    addTearDown(other.close);
    expect(await other.syncState(), isNull);
    await other.applyChanges(
      changed: [_record(price: 99, updatedAt: '2026-10-20T08:59:00Z')],
      removedIds: const [7],
      nextSince: 'x',
    );
    expect((await cache.read('4006381333931'))?['price'], 10);
  });
}
