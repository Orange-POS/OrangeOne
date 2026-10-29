import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';

Map<String, dynamic> _record(
  int id, {
  String? barcode,
  String name = 'Product',
  double price = 10,
  double? stock = 4,
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'name': '$name $id',
  'barcode': barcode ?? 'BC-$id',
  'price': price,
  'stock_quantity': stock,
  'uom': 'Units',
  'updated_at': '2026-10-20T08:00:00Z',
  ...extra,
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
      sessionSecret: 'session-a',
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

  test('starts empty', () async {
    expect(await cache.readRecents(), isEmpty);
  });

  test('keeps the newest first and moves a rescanned product up', () async {
    await cache.recordRecent(_record(1));
    await cache.recordRecent(_record(2));
    await cache.recordRecent(_record(3));
    expect((await cache.readRecents()).map((r) => r['id']), [3, 2, 1]);
    await cache.recordRecent(_record(1, price: 12));
    final recents = await cache.readRecents();
    expect(recents.map((r) => r['id']), [1, 3, 2]);
    expect(recents.first['price'], 12);
  });

  test('a product with a changed barcode is not listed twice', () async {
    await cache.recordRecent(_record(1, barcode: 'OLD'));
    await cache.recordRecent(_record(1, barcode: 'NEW'));
    final recents = await cache.readRecents();
    expect(recents, hasLength(1));
    expect(recents.single['barcode'], 'NEW');
  });

  test('keeps only the most recent products', () async {
    for (var id = 1; id <= EncryptedReadCache.recentScanLimit + 3; id++) {
      await cache.recordRecent(_record(id));
    }
    final recents = await cache.readRecents();
    expect(recents, hasLength(EncryptedReadCache.recentScanLimit));
    expect(recents.first['id'], EncryptedReadCache.recentScanLimit + 3);
    expect(recents.last['id'], 4);
  });

  test('stores only name, barcode, price, stock and unit', () async {
    await cache.recordRecent(
      _record(
        7,
        extra: {
          'default_code': 'REF',
          'description': 'Secret subtitle',
          'version': '9',
          'permissions': {'product_update_price': true},
          'taxes': [
            {'id': 1, 'name': 'VAT'},
          ],
          'category': {'id': 1, 'name': 'Spices'},
        },
      ),
    );
    expect((await cache.readRecents()).single, {
      'id': 7,
      'name': 'Product 7',
      'barcode': 'BC-7',
      'price': 10.0,
      'stock_quantity': 4.0,
      'uom': 'Units',
      'category': 'Spices',
    });
  });

  test('unknown stock stays unknown', () async {
    await cache.recordRecent(_record(1, stock: null));
    expect((await cache.readRecents()).single['stock_quantity'], isNull);
  });

  for (final (label, change) in <(String, Map<String, dynamic>)>[
    ('missing id', {'id': null}),
    ('bad id', {'id': 0}),
    ('missing barcode', {'barcode': ''}),
    ('blank name', {'name': '  '}),
    ('text price', {'price': '10'}),
    ('infinite price', {'price': double.infinity}),
    ('text stock', {'stock_quantity': 'x'}),
  ]) {
    test('ignores a record with $label', () async {
      await cache.recordRecent({..._record(1), ...change});
      expect(await cache.readRecents(), isEmpty);
    });
  }

  test('the list is encrypted and stays out of plain SQL', () async {
    await cache.recordRecent(_record(1, name: 'Private name'));
    final stored =
        (await database.customSelect('SELECT * FROM product_reads').get())
            .map((row) => row.data.toString())
            .join();
    expect(stored, isNot(contains('Private name')));
    expect(stored, isNot(contains('BC-1')));
    expect(stored, isNot(contains('session-a')));
  });

  test('survives a restart and is isolated per session', () async {
    await cache.recordRecent(_record(1));
    final restarted = EncryptedReadCache(
      database,
      sessionSecret: 'session-a',
      now: () => now,
    );
    addTearDown(restarted.close);
    expect((await restarted.readRecents()).single['id'], 1);

    final other = EncryptedReadCache(database, sessionSecret: 'session-b');
    addTearDown(other.close);
    expect(await other.readRecents(), isEmpty);
    await other.recordRecent(_record(2));
    expect((await other.readRecents()).single['id'], 2);
    expect((await cache.readRecents()).single['id'], 1);
  });

  test('closing the session deletes its recent scans', () async {
    await cache.recordRecent(_record(1));
    await cache.close();
    expect(await rows(), 0);
    expect(await cache.readRecents(), isEmpty);
    await cache.recordRecent(_record(2));
    expect(await rows(), 0, reason: 'a closed cache stores nothing');
  });

  test('a product write keeps the recent scans', () async {
    await cache.load('BC-1', () async => _record(1));
    await cache.recordRecent(_record(1));
    await cache.write(() async {});
    expect(await cache.read('BC-1'), isNull, reason: 'snapshot invalidated');
    expect((await cache.readRecents()).single['id'], 1);
  });

  test('a confirmed write refreshes the recent entry', () async {
    await cache.recordRecent(_record(1));
    await cache.put('BC-1', _record(1, price: 12.5, stock: 9));
    final item = (await cache.readRecents()).single;
    expect(item['price'], 12.5);
    expect(item['stock_quantity'], 9);
  });

  group('change feed', () {
    setUp(() async {
      await cache.load('BC-1', () async => _record(1));
      await cache.load('BC-2', () async => _record(2));
      await cache.recordRecent(_record(1));
      await cache.recordRecent(_record(2));
    });

    test('removed products leave the recent scans', () async {
      await cache.applyChanges(
        changed: const [],
        removedIds: const [1],
        nextSince: 'p1',
      );
      expect((await cache.readRecents()).map((r) => r['id']), [2]);
    });

    test('changed products refresh; a lost barcode removes them', () async {
      await cache.applyChanges(
        changed: [
          _record(1, price: 99, name: 'Renamed'),
          _record(2, extra: {'barcode': null}),
        ],
        removedIds: const [],
        nextSince: 'p1',
      );
      final recents = await cache.readRecents();
      expect(recents.map((r) => r['id']), [1]);
      expect(recents.single['price'], 99);
      expect(recents.single['name'], 'Renamed 1');
    });

    test('the recent list is not mistaken for a cached product', () async {
      await cache.resetSync();
      await cache.recordRecent(_record(5));
      expect(await cache.syncState(), isNull, reason: 'no snapshots cached');
      await cache.applyChanges(
        changed: const [],
        removedIds: const [],
        nextSince: 'x',
      );
      expect((await cache.readRecents()).single['id'], 5);
    });

    test('losing access to the feed clears the recent scans', () async {
      await cache.resetSync();
      expect(await cache.readRecents(), isEmpty);
    });
  });

  group('untrusted storage', () {
    test('tampered data is a safe storage failure and is replaced', () async {
      await cache.recordRecent(_record(1));
      final row = await database
          .customSelect('SELECT payload FROM product_reads')
          .getSingle();
      final bytes = base64Decode(row.read<String>('payload'));
      bytes[12] ^= 1;
      await database.customStatement('UPDATE product_reads SET payload = ?', [
        base64Encode(bytes),
      ]);
      await expectLater(
        cache.readRecents(),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.storage),
        ),
      );
      await cache.recordRecent(_record(2));
      expect((await cache.readRecents()).single['id'], 2);
    });

    test('a short or foreign payload is a safe storage failure', () async {
      await cache.recordRecent(_record(1));
      for (final payload in [
        base64Encode([1, 2, 3]),
        'not base64 at all',
      ]) {
        await database.customStatement('UPDATE product_reads SET payload = ?', [
          payload,
        ]);
        await expectLater(
          cache.readRecents(),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.storage,
            ),
          ),
        );
      }
    });
  });
}
