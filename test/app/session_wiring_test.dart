import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../support/auth_fakes.dart';

AuthSession _session({
  String sessionId = 'family-1',
  Uri? apiBase,
  int userId = 2,
  int companyId = 1,
}) => AuthSession(
  accessToken: 'oa_issued',
  apiBase: apiBase ?? testApiBase,
  expiresAt: testNow.add(const Duration(days: 7)),
  sessionId: sessionId,
  userId: userId,
  posConfigId: 1,
  companyId: companyId,
);

Map<String, dynamic> _product(String barcode) => {
  'id': 7,
  'name': 'Cached product',
  'barcode': barcode,
  'price': 10.0,
  'stock_quantity': 4.0,
};

Future<int> _rows(ReadCacheDatabase database) async {
  final row = await database
      .customSelect('SELECT COUNT(*) AS count FROM product_reads')
      .getSingle();
  return row.read<int>('count');
}

/// Waits for the asynchronous purge that runs when a session cache closes.
Future<int> _rowsAfterPurge(ReadCacheDatabase database) async {
  for (var i = 0; i < 100; i++) {
    if (await _rows(database) == 0) return 0;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return await _rows(database);
}

void main() {
  group('cache identity', () {
    const env = AppEnvironment.production;

    test('contains no token, so refresh keeps the identity', () {
      final identity = readCacheIdentity(env, testSession);

      expect(identity, isNot(contains(testSession.accessToken)));
      expect(identity, isNot(contains('oa_')));
      expect(
        identity,
        readCacheIdentity(
          env,
          AuthSession(
            accessToken: 'oa_refreshed',
            apiBase: testSession.apiBase,
            expiresAt: testSession.expiresAt,
            sessionId: testSession.sessionId,
            userId: testSession.userId,
            posConfigId: testSession.posConfigId,
            companyId: testSession.companyId,
          ),
        ),
      );
    });

    test(
      'differs for every other session, server, user, company and flavor',
      () {
        final base = readCacheIdentity(env, _session());
        final others = {
          readCacheIdentity(env, _session(sessionId: 'family-2')),
          readCacheIdentity(
            env,
            _session(
              apiBase: Uri.parse(
                'https://other.example/api/orangeone/mobile/v1',
              ),
            ),
          ),
          readCacheIdentity(env, _session(userId: 3)),
          readCacheIdentity(env, _session(companyId: 2)),
          readCacheIdentity(AppEnvironment.staging, _session()),
        };

        expect(others, hasLength(5));
        expect(others, isNot(contains(base)));
      },
    );

    test(
      'the same identity reads its data after a restart; others cannot',
      () async {
        final database = ReadCacheDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final identity = readCacheIdentity(env, _session());
        await EncryptedReadCache(
          database,
          sessionSecret: identity,
        ).load('4006381333931', () async => _product('4006381333931'));

        final restarted = EncryptedReadCache(database, sessionSecret: identity);
        final otherSession = EncryptedReadCache(
          database,
          sessionSecret: readCacheIdentity(
            env,
            _session(sessionId: 'family-2'),
          ),
        );

        expect(
          (await restarted.read('4006381333931'))?['name'],
          'Cached product',
        );
        expect(await otherSession.read('4006381333931'), isNull);
      },
    );
  });

  group('session wiring', () {
    late Dio dio;
    late ReadCacheDatabase database;
    late FakeAuthRepository auth;
    late List<String?> authorizations;
    late ProviderContainer container;

    setUp(() {
      dio = Dio();
      database = ReadCacheDatabase(NativeDatabase.memory());
      auth = FakeAuthRepository()..restored = testSession;
      authorizations = [];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            authorizations.add(options.headers['Authorization'] as String?);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 404,
                data: errorEnvelope('PRODUCT_NOT_FOUND'),
              ),
            );
          },
        ),
      );
      container = ProviderContainer.test(
        overrides: [
          readCacheOverride,
          authenticatedMobileApiOverride,
          productRepositoryOverride,
          productDetailsRepositoryOverride,
          readCacheDatabaseProvider.overrideWithValue(database),
          connectivityProvider.overrideWithValue(const Stream.empty()),
          environmentProvider.overrideWithValue(AppEnvironment.production),
          authRepositoryProvider.overrideWithValue(auth),
          utcNowProvider.overrideWithValue(() => testNow),
          dioProvider.overrideWithValue(dio),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      dio.close(force: true);
      await database.close();
    });

    Future<void> scan(String barcode) async {
      await container
          .read(productLookupControllerProvider.notifier)
          .scan(barcode);
      await container.pump();
    }

    test(
      'token refresh keeps repositories and cache and sends the new token',
      () async {
        await container.read(sessionControllerProvider.future);
        container
          ..listen(productLookupControllerProvider, (previous, next) {})
          ..listen(productDetailsRepositoryProvider, (previous, next) {});
        final repository = container.read(productRepositoryProvider);
        final details = container.read(productDetailsRepositoryProvider);
        final cache = container.read(readCacheProvider);
        final api = container.read(authenticatedMobileApiProvider);
        expect(cache, isNotNull);
        expect(api.apiBase, testApiBase);

        await scan('4006381333931');
        auth.currentToken = 'oa_refreshed';
        await scan('4006381333948');

        expect(authorizations, [
          'Bearer ${testSession.accessToken}',
          'Bearer oa_refreshed',
        ]);
        expect(container.read(productRepositoryProvider), same(repository));
        expect(container.read(productDetailsRepositoryProvider), same(details));
        expect(container.read(readCacheProvider), same(cache));
        expect(container.read(authenticatedMobileApiProvider), same(api));
        expect(auth.tokenRequests, 2);
      },
    );

    test('cached data survives token refresh', () async {
      await container.read(sessionControllerProvider.future);
      final cache = container.read(readCacheProvider)!;
      await cache.load('4006381333931', () async => _product('4006381333931'));
      expect(await _rows(database), 1);

      auth.currentToken = 'oa_refreshed';
      await container.read(sessionControllerProvider.notifier).accessToken();
      await container.pump();

      expect(container.read(readCacheProvider), same(cache));
      expect(await _rows(database), 1);
      expect((await cache.read('4006381333931'))?['name'], 'Cached product');
    });

    test('logout purges the session cache and closes the wiring', () async {
      await container.read(sessionControllerProvider.future);
      final cache = container.read(readCacheProvider)!;
      await cache.load('4006381333931', () async => _product('4006381333931'));

      await container.read(sessionControllerProvider.notifier).signOut();
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(readCacheProvider), isNull);
      expect(await _rowsAfterPurge(database), 0);
      expect(
        () => container.read(authenticatedMobileApiProvider),
        throwsA(anything),
      );
    });

    test('a rejected refresh signs out and removes cached data', () async {
      await container.read(sessionControllerProvider.future);
      await container
          .read(readCacheProvider)!
          .load('4006381333931', () async => _product('4006381333931'));
      auth.tokenFailure = invalidSession;

      await expectLater(
        container.read(sessionControllerProvider.notifier).accessToken(),
        throwsA(same(invalidSession)),
      );
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sessionControllerProvider).value, isNull);
      expect(container.read(readCacheProvider), isNull);
      expect(await _rowsAfterPurge(database), 0);
    });

    test(
      'the next session gets a separate cache without previous data',
      () async {
        await container.read(sessionControllerProvider.future);
        final first = container.read(readCacheProvider)!;
        await first.load(
          '4006381333931',
          () async => _product('4006381333931'),
        );
        await container.read(sessionControllerProvider.notifier).signOut();
        await container.pump();

        auth.pendingLogin = Completer<AuthSession>()
          ..complete(_session(sessionId: 'family-2', userId: 3));
        await container.read(sessionControllerProvider.notifier).signIn('qr');
        await container.pump();

        final second = container.read(readCacheProvider)!;
        expect(second, isNot(same(first)));
        expect(await second.read('4006381333931'), isNull);
      },
    );
  });
}
