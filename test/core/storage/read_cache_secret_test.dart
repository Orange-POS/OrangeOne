import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_secret.dart';

import '../../support/auth_fakes.dart';

// AUD-05 and AUD-06: the cache key needs a stored random secret, and rows
// of other owners are swept.
void main() {
  const identity = 'production|http://192.168.1.2|1|2|family-1';
  const product = <String, dynamic>{
    'id': 1,
    'name': 'Private product',
    'barcode': '00123',
    'price': 2.5,
  };

  group('ReadCacheSecret', () {
    late MemorySecretStore store;
    late ReadCacheSecret secrets;
    setUp(() {
      store = MemorySecretStore();
      secrets = ReadCacheSecret(store, environment: 'production');
    });

    test(
      'one random secret per session identity, kept across restarts',
      () async {
        final first = await secrets.secretFor(identity);
        expect(first.length, greaterThanOrEqualTo(43));
        expect(store.values.values.single, isNot(contains(identity)));
        // A restart of the same session reads the same secret.
        final restarted = ReadCacheSecret(store, environment: 'production');
        expect(await restarted.secretFor(identity), first);
        // Another session gets a new one that replaces it.
        final other = await secrets.secretFor('$identity-2');
        expect(other, isNot(first));
        expect(await secrets.secretFor(identity), isNot(first));
      },
    );

    // CodeRabbit: cleanup of an ended session and a new session's secret
    // run one at a time across instances.
    test('an ended session cleanup never deletes a newer secret', () async {
      const next = '$identity-next';
      await secrets.secretFor(identity);
      // The old session's cleanup is slow to delete.
      store.pendingDelete = Completer<void>();
      final cleanup = secrets.deleteFor(identity);
      // Meanwhile the next session's cache (its own instance) gets a secret.
      final newer = ReadCacheSecret(
        store,
        environment: 'production',
      ).secretFor(next);
      await pumpEventQueue();
      store.pendingDelete!.complete();
      await cleanup;
      final secret = await newer;
      store.pendingDelete = null;
      // A restart of the next session finds the same secret.
      expect(
        await ReadCacheSecret(store, environment: 'production').secretFor(next),
        secret,
      );
    });

    test('a failed operation does not block the next one', () async {
      store.failure = storageFailure;
      await expectLater(secrets.secretFor(identity), throwsA(storageFailure));
      store.failure = null;
      expect(await secrets.secretFor(identity), isNotEmpty);
    });

    test('deleting removes only the ended session secret', () async {
      await secrets.secretFor(identity);
      await secrets.deleteFor('another-session');
      expect(store.values, hasLength(1));
      await secrets.deleteFor(identity);
      expect(store.values, isEmpty);
    });
  });

  group('EncryptedReadCache with a stored secret', () {
    late ReadCacheDatabase database;
    setUp(() => database = ReadCacheDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    EncryptedReadCache cacheWith(String? secret) => EncryptedReadCache(
      database,
      sessionSecret: identity,
      keySecret: secret == null ? null : () async => secret,
    );

    test('the identity alone cannot read the rows', () async {
      final cache = cacheWith('secret-a');
      await cache.load('00123', () async => product);
      expect((await cache.read('00123'))?['name'], 'Private product');
      expect(await cacheWith(null).read('00123'), isNull);
      expect(await cacheWith('secret-b').read('00123'), isNull);
      await cache.close();
    });

    test('a new session sweeps rows its predecessor never closed', () async {
      // The app was stopped: this cache is never closed.
      await cacheWith('secret-a').load('00123', () async => product);
      final next = cacheWith('secret-b');
      await next.load('00456', () async => {...product, 'barcode': '00456'});
      await next.purgeOtherOwners();
      final rows = await database
          .customSelect('SELECT owner FROM product_reads')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('owner'), await next.owner);
      expect((await next.read('00456'))?['barcode'], '00456');
      await next.close();
    });

    test('a failed secret read is retried, not kept', () async {
      var calls = 0;
      final cache = EncryptedReadCache(
        database,
        sessionSecret: identity,
        keySecret: () async {
          if (++calls == 1) throw StateError('keychain locked');
          return 'secret-a';
        },
      );
      await expectLater(cache.owner, throwsStateError);
      expect(await cache.owner, isNotEmpty);
      expect(calls, 2);
      await cache.close();
    });
  });
}
