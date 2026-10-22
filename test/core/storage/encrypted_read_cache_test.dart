import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';

const product = <String, dynamic>{
  'id': 1,
  'name': 'Private product',
  'barcode': '00123',
  'price': 2.5,
  'stock_quantity': 8,
  'uom': 'Units',
};
const network = AppFailure(FailureKind.network, 'Offline');

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  late DateTime now;
  setUp(() {
    database = ReadCacheDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 20);
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

  test('encrypts approved fields and keeps barcode/token out of SQL', () async {
    await cache.load(
      '00123',
      () async => {...product, 'access_token': 'secret'},
    );
    final rows = await database
        .customSelect('SELECT * FROM product_reads')
        .get();
    expect(rows, hasLength(1));
    final stored = rows.single.data.toString();
    expect(stored, isNot(contains('Private product')));
    expect(stored, isNot(contains('00123')));
    expect(stored, isNot(contains('synthetic-session')));
    final saved = await cache.read('00123');
    expect(saved?['name'], 'Private product');
    expect(saved, isNot(contains('access_token')));
  });

  test('fallback is stale and offline reads do not repeatedly ping', () async {
    var requests = 0;
    await cache.load('00123', () async => product);
    final value = await cache.load('00123', () async {
      requests++;
      throw network;
    });
    expect(value?['id'], 1);
    expect(cache.status('00123').phase, ReadSyncPhase.offline);
    expect(cache.status('00123').verifiedAt, isNotNull);
    await cache.load('00123', () async {
      requests++;
      return product;
    });
    expect(requests, 1);
  });

  test('a cache miss is a network error, never a not-found product', () async {
    await expectLater(
      cache.load('missing', () async => throw network),
      throwsA(same(network)),
    );
  });

  test('offline mutations are blocked before invoking the backend', () async {
    cache.connectionChanged(connected: false);
    var writes = 0;
    await expectLater(
      cache.write(() async {
        writes++;
      }),
      throwsA(isA<AppFailure>()),
    );
    expect(writes, 0);
  });

  test(
    'recovery requires verified server read before enabling writes',
    () async {
      await cache.load('00123', () async => product);
      cache.connectionChanged(connected: false);
      final signal = cache.recovery.first;
      cache.connectionChanged(connected: true);
      await signal;
      expect(cache.offline, isTrue);
      await cache.load('00123', () async => {...product, 'price': 3.0});
      expect(cache.offline, isFalse);
      expect(cache.status('00123').phase, ReadSyncPhase.online);
      expect((await cache.read('00123'))?['price'], 3);
    },
  );

  test('coalesces concurrent reads into one request', () async {
    var requests = 0;
    final pending = Completer<Map<String, dynamic>?>();
    Future<Map<String, dynamic>?> fetch() {
      requests++;
      return pending.future;
    }

    final a = cache.load('00123', fetch);
    final b = cache.load('00123', fetch);
    expect(cache.status('00123').phase, ReadSyncPhase.pending);
    pending.complete(product);
    await Future.wait([a, b]);
    expect(requests, 1);
  });

  test('confirmed not-found removes previously cached product', () async {
    await cache.load('00123', () async => product);
    expect(await cache.load('00123', () async => null), isNull);
    expect(await cache.read('00123'), isNull);
  });

  test('auth rejection never falls back to cached inventory', () async {
    await cache.load('00123', () async => product);
    await expectLater(
      cache.load('00123', () async => throw invalidSession),
      throwsA(same(invalidSession)),
    );
    expect(await cache.read('00123'), isNull);
    expect(cache.status('00123').phase, ReadSyncPhase.failed);
  });

  test('new session cannot read another session data', () async {
    await cache.load('00123', () async => product);
    final other = EncryptedReadCache(
      database,
      sessionSecret: 'different-session',
    );
    expect(await other.read('00123'), isNull);
    await other.close();
    expect((await cache.read('00123'))?['id'], 1);
  });

  test(
    'uncertain write clears old data and is not queued or retried',
    () async {
      await cache.load('00123', () async => product);
      var writes = 0;
      await expectLater(
        cache.write(() async {
          writes++;
          throw network;
        }),
        throwsA(same(network)),
      );
      expect(writes, 1);
      expect(await cache.read('00123'), isNull);
      expect(cache.offline, isTrue);
    },
  );

  test('read completing after mutation cannot repopulate stale data', () async {
    final pending = Completer<Map<String, dynamic>?>();
    final read = cache.load('00123', () => pending.future);
    final assertion = expectLater(read, throwsA(same(cancelledOperation)));
    await cache.write(() async {});
    pending.complete(product);
    await assertion;
    expect(await cache.read('00123'), isNull);
  });

  test('tampered payload is a safe storage failure', () async {
    await cache.load('00123', () async => product);
    await database.customStatement(
      "UPDATE product_reads SET payload = 'invalid'",
    );
    await expectLater(cache.read('00123'), throwsA(isA<AppFailure>()));
  });
  test('changed ciphertext byte is a typed failed storage read', () async {
    await cache.load('00123', () async => product);
    final row = await database
        .customSelect('SELECT payload FROM product_reads')
        .getSingle();
    final bytes = base64Decode(row.read<String>('payload'));
    bytes[12] ^= 1; // Corrupt ciphertext while keeping a valid envelope/nonce.
    await database.customStatement('UPDATE product_reads SET payload = ?', [
      base64Encode(bytes),
    ]);
    await expectLater(
      cache.read('00123'),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          FailureKind.storage,
        ),
      ),
    );
    expect(cache.status('00123').phase, ReadSyncPhase.failed);
  });

  test('short encrypted envelope cannot escape as ArgumentError', () async {
    await cache.load('00123', () async => product);
    await database.customStatement('UPDATE product_reads SET payload = ?', [
      base64Encode([1, 2, 3]),
    ]);
    await expectLater(
      cache.read('00123'),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          FailureKind.storage,
        ),
      ),
    );
    expect(cache.status('00123').phase, ReadSyncPhase.failed);
  });

  test('cached data older than one day is not served', () async {
    await cache.load('00123', () async => product);
    now = now.add(const Duration(hours: 25));
    expect(await cache.read('00123'), isNull);
  });

  test('duplicate mutations are blocked instead of queued', () async {
    final pending = Completer<void>();
    var duplicates = 0;
    final operation = cache.write(() => pending.future);
    await expectLater(
      cache.write(() async {
        duplicates++;
      }),
      throwsA(isA<AppFailure>()),
    );
    pending.complete();
    await operation;
    expect(duplicates, 0);
  });

  test('logout removes session records and rejects late reads', () async {
    await cache.load('00123', () async => product);
    await cache.close();
    final rows = await database
        .customSelect('SELECT * FROM product_reads')
        .get();
    expect(rows, isEmpty);
    await expectLater(
      cache.load('00123', () async => product),
      throwsA(same(cancelledOperation)),
    );
  });
}
