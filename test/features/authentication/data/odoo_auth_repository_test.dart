import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/features/authentication/data/data_sources/auth_remote_data_source.dart';
import 'package:orange_one/features/authentication/data/models/device_model.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';
import 'package:orange_one/features/authentication/data/repositories/odoo_auth_repository.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/mobile_api_fakes.dart';

void main() {
  const config = ApiConfiguration(
    baseUrl: 'https://fallback.example',
    environment: AppEnvironment.development,
  );
  const key = 'orangeone.development.session.v2';
  const legacyKey = 'orangeone.development.session.v1';
  const installKey = 'orangeone.development.install_id';

  late Dio dio;
  late FakeMobileApiServer server;
  late MemorySecretStore store;
  late OdooAuthRepository repository;
  late DateTime now;

  OdooAuthRepository build() => OdooAuthRepository(
    AuthRemoteDataSource(MobileApiClient(dio, config)),
    store,
    config,
    () => now,
    platform: 'android',
    appVersion: '1.2.3',
  );

  setUp(() {
    now = testNow;
    dio = Dio();
    server = FakeMobileApiServer();
    dio.httpClientAdapter = server;
    store = MemorySecretStore();
    repository = build();
    server
      ..on(
        'POST /auth/qr-exchange',
        (_) => FakeReply(200, successEnvelope(tokenGrant())),
      )
      ..on(
        'GET /auth/session',
        (_) => FakeReply(200, successEnvelope(sessionPayload())),
      )
      ..on(
        'POST /auth/token/refresh',
        (_) => FakeReply(
          200,
          successEnvelope(tokenGrant(access: 'oa_access_2', refresh: 'or_2')),
        ),
      )
      ..on('POST /auth/logout', (_) => const FakeReply(204));
  });
  tearDown(() {
    repository.dispose();
    dio.close(force: true);
  });

  SessionCredentials stored() =>
      SessionModel.decode(store.values[key]!, config);

  /// Persists a signed-in session as a previous app run would have.
  void storeSession({Duration accessLifetime = const Duration(minutes: 15)}) {
    store.values[installKey] = '0f8fad5b-d9cb-469f-a165-70867728950e';
    store.values[key] = SessionModel.encode(
      SessionModel.fromGrant(
        tokenGrant(accessLifetime: accessLifetime),
        testApiBase,
      ),
    );
  }

  group('QR sign-in', () {
    test(
      'exchanges the QR at its API base and persists after confirmation',
      () async {
        final session = await repository.signIn(validQr());

        final request = server.called('POST /auth/qr-exchange').single;
        expect(
          request.uri.toString(),
          'https://pos.example/api/orangeone/mobile/v1/auth/qr-exchange',
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        final body = requestBody(request);
        expect(body['challenge_id'], qrFields()['challenge_id']);
        expect(body['nonce'], qrFields()['nonce']);
        expect(body['pos_config_id'], 1);
        final device = body['device'] as Map<String, dynamic>;
        expect(DeviceModel.isInstallId(device['install_id'] as String), isTrue);
        expect(device['platform'], 'android');
        expect(device['app_version'], '1.2.3');

        expect(session.accessToken, 'oa_access_1');
        expect(session.sessionId, 'family-1');
        expect(session.userId, 2);
        expect(session.companyId, 1);
        expect(session.posConfigId, 1);
        expect(session.posSessionId, 106);
        expect(session.employeeId, isNull);
        expect(session.expiresAt, testNow.add(const Duration(days: 7)));
        expect(session.backendOrigin, testOrigin);
        expect(session.toString(), 'AuthSession(redacted)');

        expect(stored().refreshToken, 'or_refresh_1');
        expect(stored().toString(), 'SessionCredentials(redacted)');
        expect(store.values[installKey], device['install_id']);
        expect(await repository.accessToken(), 'oa_access_1');
      },
    );

    test('reuses the install id across sign-ins and logout', () async {
      await repository.signIn(validQr());
      await repository.signOut();
      await repository.signIn(validQr());

      final ids = [
        for (final request in server.called('POST /auth/qr-exchange'))
          (requestBody(request)['device'] as Map)['install_id'],
      ];
      expect(ids.toSet(), hasLength(1));
      expect(store.values[installKey], ids.first);
    });

    test('uses the scanned server with a path prefix', () async {
      const base = 'http://192.168.1.3:8069/odoo/api/orangeone/mobile/v1';
      final qr = jsonEncode({...qrFields(), 'api_base': base});

      final session = await repository.signIn(qr);

      expect(server.requests.single.uri.toString(), '$base/auth/qr-exchange');
      expect(session.apiBase, Uri.parse(base));
      expect(session.backendOrigin, Uri.parse('http://192.168.1.3:8069'));
    });

    for (final field in [
      'token_type',
      'access_token',
      'refresh_token',
      'access_expires_at',
      'refresh_expires_at',
      'session',
    ]) {
      test('rejects a grant without $field before persisting', () async {
        server.on(
          'POST /auth/qr-exchange',
          (_) => FakeReply(200, successEnvelope(tokenGrant()..remove(field))),
        );

        await expectLater(
          repository.signIn(validQr()),
          throwsA(isA<AppFailure>()),
        );
        expect(store.values.containsKey(key), isFalse);
      });
    }

    test('rejects a grant for another POS config', () async {
      server.on(
        'POST /auth/qr-exchange',
        (_) => FakeReply(
          200,
          successEnvelope(tokenGrant(session: sessionPayload(posConfigId: 9))),
        ),
      );

      await expectLater(
        repository.signIn(validQr()),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
        ),
      );
      expect(store.values.containsKey(key), isFalse);
    });

    for (final entry in {
      'QR_EXPIRED': FailureKind.expiredQr,
      'QR_USED': FailureKind.usedQr,
      'QR_INVALID': FailureKind.validation,
      'APP_UPGRADE_REQUIRED': FailureKind.upgradeRequired,
      'INTERNAL_ERROR': FailureKind.backend,
    }.entries) {
      test('maps ${entry.key} by error code', () async {
        server.on(
          'POST /auth/qr-exchange',
          (_) => FakeReply(401, errorEnvelope(entry.key)),
        );

        await expectLater(
          repository.signIn(validQr()),
          throwsA(
            isA<AppFailure>()
                .having((e) => e.kind, 'kind', entry.value)
                .having((e) => e.code, 'code', entry.key),
          ),
        );
        expect(store.values.containsKey(key), isFalse);
      });
    }

    test('invalid QR data never reaches the server', () async {
      await expectLater(repository.signIn('{"v":2}'), throwsA(same(invalidQr)));
      expect(server.requests, isEmpty);
    });

    test('secure-storage failure prevents successful sign-in', () async {
      store.failure = storageFailure;

      await expectLater(
        repository.signIn(validQr()),
        throwsA(same(storageFailure)),
      );
      expect(server.requests, isEmpty);
    });

    test(
      'logout serialized after an in-flight write leaves no token behind',
      () async {
        store.values[installKey] = '0f8fad5b-d9cb-469f-a165-70867728950e';
        store.pendingWrite = Completer<void>();
        final signIn = repository.signIn(validQr());
        final rejectedLogin = expectLater(signIn, throwsA(isA<AppFailure>()));
        while (store.writes == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        final signOut = repository.signOut();
        store.pendingWrite!.complete();
        await signOut;
        await rejectedLogin;
        expect(store.values.containsKey(key), isFalse);
      },
    );
  });

  group('restore', () {
    test('validates the stored session with /auth/session', () async {
      storeSession();

      final session = await repository.restore();

      expect(session?.sessionId, 'family-1');
      final request = server.called('GET /auth/session').single;
      expect(request.headers['Authorization'], 'Bearer oa_access_1');
      expect(server.called('POST /auth/token/refresh'), isEmpty);
      expect(await repository.accessToken(), 'oa_access_1');
    });

    test('refreshes an expired access token before validating', () async {
      storeSession(accessLifetime: const Duration(seconds: 10));

      final session = await repository.restore();

      expect(session?.accessToken, 'oa_access_2');
      final refresh = server.called('POST /auth/token/refresh').single;
      expect(requestBody(refresh), {
        'refresh_token': 'or_refresh_1',
        'install_id': '0f8fad5b-d9cb-469f-a165-70867728950e',
      });
      expect(
        server.called('GET /auth/session').single.headers['Authorization'],
        'Bearer oa_access_2',
      );
      expect(stored().refreshToken, 'or_2');
    });

    test('refreshes once when the server reports TOKEN_EXPIRED', () async {
      storeSession();
      var calls = 0;
      server.on(
        'GET /auth/session',
        (_) => ++calls == 1
            ? FakeReply(401, errorEnvelope('TOKEN_EXPIRED'))
            : FakeReply(200, successEnvelope(sessionPayload())),
      );

      final session = await repository.restore();

      expect(session?.accessToken, 'oa_access_2');
      expect(server.called('POST /auth/token/refresh'), hasLength(1));
      expect(server.called('GET /auth/session'), hasLength(2));
    });

    for (final code in ['TOKEN_REVOKED', 'TOKEN_INVALID', 'DEVICE_MISMATCH']) {
      test('$code during refresh clears the stored session', () async {
        storeSession(accessLifetime: Duration.zero);
        server.on(
          'POST /auth/token/refresh',
          (_) => FakeReply(
            code == 'DEVICE_MISMATCH' ? 403 : 401,
            errorEnvelope(code),
          ),
        );

        expect(await repository.restore(), isNull);
        expect(store.values.containsKey(key), isFalse);
        expect(store.values.containsKey(installKey), isTrue);
      });
    }

    test('a session of another identity is rejected', () async {
      storeSession();
      server.on(
        'GET /auth/session',
        (_) => FakeReply(200, successEnvelope(sessionPayload(companyId: 99))),
      );

      expect(await repository.restore(), isNull);
      expect(store.values.containsKey(key), isFalse);
    });

    test('an ended sign-in is cleared without a backend call', () async {
      storeSession();
      now = testNow.add(const Duration(days: 8));

      expect(await repository.restore(), isNull);
      expect(store.values.containsKey(key), isFalse);
      expect(server.requests, isEmpty);
    });

    test('malformed storage is cleared without authorizing the app', () async {
      store.values[key] = '{broken';

      expect(await repository.restore(), isNull);
      expect(store.values.containsKey(key), isFalse);
      expect(server.requests, isEmpty);
    });

    test('a version 1 session is deleted and needs a new QR login', () async {
      store.values[legacyKey] = jsonEncode({'access_token': 'a.b.c'});

      expect(await repository.restore(), isNull);
      expect(store.values.containsKey(legacyKey), isFalse);
      expect(server.requests, isEmpty);
    });

    test('empty storage never calls the server', () async {
      expect(await repository.restore(), isNull);
      expect(server.requests, isEmpty);
    });

    test('first network failure deletes secrets without retrying', () async {
      storeSession();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            server.requests.add(options);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      expect(await repository.restore(), isNull);
      expect(store.values.containsKey(key), isFalse);
      expect(server.requests, hasLength(1));
      expect(await repository.restore(), isNull);
      expect(server.requests, hasLength(1));
    });

    test(
      'startup check cancels at 15 seconds and ignores late success',
      () async {
        storeSession();
        final reply = Completer<FakeReply>();
        server.on('GET /auth/session', (_) => reply.future);

        expect(await repository.restore(), isNull);
        expect(store.values.containsKey(key), isFalse);
        expect(server.requests.single.cancelToken!.isCancelled, isTrue);
        reply.complete(FakeReply(200, successEnvelope(sessionPayload())));
        await Future<void>.delayed(Duration.zero);
        expect(store.values.containsKey(key), isFalse);
        expect(server.requests, hasLength(1));
      },
    );

    test(
      'stalled cleanup reports a storage error and blocks login until deletion',
      () async {
        store.values[key] = '{broken';
        store.pendingDelete = Completer<void>();

        await expectLater(
          repository.restore().timeout(const Duration(seconds: 3)),
          throwsA(same(storageFailure)),
        );
        expect(store.values.containsKey(key), isTrue);
        await expectLater(
          repository.signIn(validQr()),
          throwsA(same(storageFailure)),
        );
        expect(server.requests, isEmpty);

        store.pendingDelete!.complete();
        await Future<void>.delayed(Duration.zero);
        expect(store.values.containsKey(key), isFalse);
        await repository.signIn(validQr());
        expect(store.values.containsKey(key), isTrue);
      },
    );
  });

  group('access token refresh', () {
    test('returns a valid token without a request', () async {
      await repository.signIn(validQr());

      expect(await repository.accessToken(), 'oa_access_1');
      expect(server.called('POST /auth/token/refresh'), isEmpty);
    });

    test(
      'concurrent callers share one refresh and the rotation is stored',
      () async {
        await repository.signIn(validQr());
        now = testNow.add(const Duration(minutes: 15));
        final reply = Completer<FakeReply>();
        server.on('POST /auth/token/refresh', (_) => reply.future);

        final tokens = Future.wait([
          repository.accessToken(),
          repository.accessToken(),
          repository.refreshAccessToken('oa_access_1'),
        ]);
        await Future<void>.delayed(Duration.zero);
        reply.complete(
          FakeReply(
            200,
            successEnvelope(tokenGrant(access: 'oa_access_2', refresh: 'or_2')),
          ),
        );

        expect(await tokens, ['oa_access_2', 'oa_access_2', 'oa_access_2']);
        expect(server.called('POST /auth/token/refresh'), hasLength(1));
        expect(
          requestBody(
            server.called('POST /auth/token/refresh').single,
          )['refresh_token'],
          'or_refresh_1',
        );
        expect(stored().accessToken, 'oa_access_2');
        expect(stored().refreshToken, 'or_2');
      },
    );

    test(
      'a token rejected after another caller refreshed is not refreshed again',
      () async {
        await repository.signIn(validQr());

        expect(
          await repository.refreshAccessToken('oa_access_1'),
          'oa_access_2',
        );
        expect(
          await repository.refreshAccessToken('oa_access_1'),
          'oa_access_2',
        );
        expect(server.called('POST /auth/token/refresh'), hasLength(1));
      },
    );

    test('a revoked refresh token ends the session', () async {
      await repository.signIn(validQr());
      server.on(
        'POST /auth/token/refresh',
        (_) => FakeReply(401, errorEnvelope('TOKEN_REVOKED')),
      );

      await expectLater(
        repository.refreshAccessToken('oa_access_1'),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', FailureKind.unauthenticated)
              .having((e) => e.code, 'code', 'TOKEN_REVOKED'),
        ),
      );
    });

    test('a device mismatch is reported as an invalid session', () async {
      await repository.signIn(validQr());
      server.on(
        'POST /auth/token/refresh',
        (_) => FakeReply(403, errorEnvelope('DEVICE_MISMATCH')),
      );

      await expectLater(
        repository.refreshAccessToken('oa_access_1'),
        throwsA(same(invalidSession)),
      );
    });

    test('a network failure keeps the session for a later retry', () async {
      await repository.signIn(validQr());
      server.on(
        'POST /auth/token/refresh',
        (request) => throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.refreshAccessToken('oa_access_1'),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.network),
        ),
      );
      server.on(
        'POST /auth/token/refresh',
        (_) =>
            FakeReply(200, successEnvelope(tokenGrant(access: 'oa_access_2'))),
      );
      expect(await repository.refreshAccessToken('oa_access_1'), 'oa_access_2');
    });

    test('an ended sign-in cannot be refreshed', () async {
      await repository.signIn(validQr());
      now = testNow.add(const Duration(days: 8));

      await expectLater(
        repository.accessToken(),
        throwsA(same(invalidSession)),
      );
      expect(server.called('POST /auth/token/refresh'), isEmpty);
    });

    test('no session means no token', () async {
      await expectLater(
        repository.accessToken(),
        throwsA(same(invalidSession)),
      );
    });
  });

  group('logout', () {
    test(
      'revokes the session on the server and clears local credentials',
      () async {
        await repository.signIn(validQr());

        await repository.signOut();
        expect(store.values.containsKey(key), isFalse);
        // The server logout is sent in the background after local cleanup.
        for (var i = 0; i < 100; i++) {
          if (server.called('POST /auth/logout').isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        final request = server.called('POST /auth/logout').single;
        expect(request.headers['Authorization'], 'Bearer oa_access_1');
        expect(store.values.containsKey(key), isFalse);
        await expectLater(
          repository.accessToken(),
          throwsA(same(invalidSession)),
        );
      },
    );

    test('local cleanup does not wait for an unreachable server', () async {
      await repository.signIn(validQr());
      server.on('POST /auth/logout', (_) => FakeReply.hang);

      await repository.signOut().timeout(const Duration(seconds: 1));

      expect(store.values.containsKey(key), isFalse);
    });

    test('a failed server logout still signs out locally', () async {
      await repository.signIn(validQr());
      server.on(
        'POST /auth/logout',
        (_) => FakeReply(500, errorEnvelope('INTERNAL_ERROR')),
      );

      await repository.signOut();

      expect(store.values.containsKey(key), isFalse);
    });

    test('signing out with no session sends nothing', () async {
      await repository.signOut();

      expect(server.requests, isEmpty);
    });
  });
}
