import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/features/authentication/data/data_sources/auth_remote_data_source.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';
import 'package:orange_one/features/authentication/data/repositories/odoo_auth_repository.dart';

import '../../../support/auth_fakes.dart';

void main() {
  late Dio dio;
  late MemorySecretStore store;
  late OdooAuthRepository repository;
  late Map<String, dynamic> result;
  late List<RequestOptions> requests;
  setUp(() {
    dio = Dio();
    store = MemorySecretStore();
    result = tokenResult();
    requests = [];
    const config = ApiConfiguration(
      baseUrl: 'https://pos.example',
      environment: AppEnvironment.development,
    );
    repository = OdooAuthRepository(
      AuthRemoteDataSource(JsonRpcClient(dio, config)),
      store,
      config,
      () => testNow,
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'jsonrpc': '2.0',
                'id': (options.data as Map)['id'],
                'result': result,
              },
            ),
          );
        },
      ),
    );
  });
  tearDown(() {
    repository.dispose();
    dio.close(force: true);
  });
  const key = 'orangeone.development.session.v1';

  test(
    'stalled cleanup reports storage error and blocks login until deletion',
    () async {
      store.values[key] = '{broken';
      store.pendingDelete = Completer<void>();
      await expectLater(
        repository.restore().timeout(const Duration(seconds: 3)),
        throwsA(same(storageFailure)),
      );
      expect(store.values.containsKey(key), isTrue);
      expect(store.deletes, 1);
      await expectLater(
        repository.signIn(validQr()),
        throwsA(same(storageFailure)),
      );
      expect(requests, isEmpty);
      store.pendingDelete!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(store.values, isEmpty);
      await repository.signIn(validQr());
      expect(store.values.containsKey(key), isTrue);
      expect(store.deletes, 1);
    },
  );

  test(
    'validation deadline plus stalled cleanup returns a safe storage error',
    () async {
      store.values[key] = SessionModel.encode(testSession);
      store.pendingDelete = Completer<void>();
      final requested = Completer<RequestOptions>();
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            requested.complete(options);
          },
        ),
      );
      final restoration = repository.restore();
      final assertion = expectLater(
        restoration.timeout(const Duration(seconds: 18)),
        throwsA(same(storageFailure)),
      );
      final request = await requested.future;
      await assertion;
      expect(request.cancelToken!.isCancelled, isTrue);
      expect(store.values.containsKey(key), isTrue);
      expect(store.deletes, 1);
      expect(requests, hasLength(1));
      store.pendingDelete!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(store.values, isEmpty);
    },
  );

  test(
    'login and restored token use the scanned server, not configuration',
    () async {
      const server = 'http://192.168.1.3:8080';
      final session = await repository.signIn(
        jsonEncode({
          ...qrFields(),
          'backend_url': server,
          'rest_endpoint_url': '$server/mupi/mobile/auth/challenge/validate',
        }),
      );
      expect(session.backendOrigin, Uri.parse(server));
      expect(requests.single.uri.origin, server);
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
      final restored = await repository.restore();
      expect(restored?.backendOrigin, Uri.parse(server));
      expect(requests.last.uri.origin, server);
      expect(
        requests.last.headers['Authorization'],
        'Bearer ${session.accessToken}',
      );
      await repository.signOut();
      await repository.signIn(validQr());
      expect(requests.last.uri.origin, testOrigin.toString());
      expect(requests.last.headers.containsKey('Authorization'), isFalse);
    },
  );

  test(
    'signs in with exact contract and persists only after confirmation',
    () async {
      final session = await repository.signIn(validQr());
      expect(session.userId, 2);
      expect(session.employeeId, isNull);
      expect(session.expiresAt, testNow.add(const Duration(hours: 8)));
      expect(session.toString(), 'AuthSession(redacted)');
      expect(requests.single.uri.path, '/mupi/mobile/auth/challenge/validate');
      final params = (requests.single.data as Map)['params'] as Map;
      expect(
        params.keys,
        containsAll(['challenge', 'nonce', 'pos_session_id', 'pos_config_id']),
      );
      expect(store.writes, 1);
      expect(
        SessionModel.decode(
          store.values[key]!,
          const ApiConfiguration(
            baseUrl: '',
            environment: AppEnvironment.development,
          ),
        ).tokenId,
        7,
      );
    },
  );

  test(
    'validates a persisted token with the server before restoration',
    () async {
      store.values[key] = SessionModel.encode(testSession);
      final session = await repository.restore();
      expect(session?.userId, 2);
      expect(requests.single.uri.path, '/mupi/mobile/auth/token/check');
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${testSession.accessToken}',
      );
    },
  );

  test('empty storage never calls the server', () async {
    expect(await repository.restore(), isNull);
    expect(requests, isEmpty);
  });

  test('expired storage is cleared without a backend call', () async {
    store.values[key] = SessionModel.encode(testSession)
        .replaceFirst('2030-01-01T20:00:00.000Z', '2029-01-01T20:00:00.000Z');
    expect(await repository.restore(), isNull);
    expect(store.values, isEmpty);
    expect(requests, isEmpty);
  });

  test('malformed storage is cleared without authorizing the app', () async {
    store.values[key] = '{broken';
    expect(await repository.restore(), isNull);
    expect(store.values, isEmpty);
  });

  test('revoked token is cleared on server rejection', () async {
    store.values[key] = SessionModel.encode(testSession);
    result = {'ok': false, 'error': 'Token is not active.'};
    expect(await repository.restore(), isNull);
    expect(store.values, isEmpty);
  });

  test('mismatched token identity is rejected', () async {
    store.values[key] = SessionModel.encode(testSession);
    result['company_id'] = 99;
    expect(await repository.restore(), isNull);
    expect(store.values, isEmpty);
  });

  for (final field in [
    'access_token',
    'token_type',
    'expires_at',
    'token_id',
    'user_id',
    'company_id',
    'pos_session_id',
    'pos_config_id',
  ]) {
    test('rejects missing required $field before persisting', () async {
      result.remove(field);
      await expectLater(
        repository.signIn(validQr()),
        throwsA(isA<AppFailure>()),
      );
      expect(store.writes, 0);
    });
  }

  for (final entry in {
    'This QR code has expired.': FailureKind.expiredQr,
    'This QR code has already been used.': FailureKind.usedQr,
    'Invalid QR code verification data.': FailureKind.validation,
    'unrecognized secret server trace': FailureKind.backend,
  }.entries) {
    test('maps backend ${entry.value} without exposing backend text', () async {
      result = {'ok': false, 'error': entry.key};
      await expectLater(
        repository.signIn(validQr()),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', entry.value)),
      );
      expect(store.writes, 0);
    });
  }

  test('secure-storage failure prevents successful sign-in', () async {
    store.failure = storageFailure;
    await expectLater(
      repository.signIn(validQr()),
      throwsA(same(storageFailure)),
    );
  });

  test(
    'logout serialized after an in-flight write leaves no token behind',
    () async {
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
      expect(store.values, isEmpty);
    },
  );

  test(
    'first network failure on restore deletes secrets without retrying',
    () async {
      store.values[key] = SessionModel.encode(testSession);
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
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
      expect(store.values, isEmpty);
      expect(requests, hasLength(1));
      expect(await repository.restore(), isNull);
      expect(requests, hasLength(1));
    },
  );

  test(
    'startup check cancels at 15 seconds and ignores late success',
    () async {
      store.values[key] = SessionModel.encode(testSession);
      final requested = Completer<void>();
      RequestInterceptorHandler? pending;
      RequestOptions? request;
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            request = options;
            pending = handler;
            requested.complete();
          },
        ),
      );
      var completed = false;
      final restoration = repository.restore().then((value) {
        completed = true;
        return value;
      });
      await requested.future;
      expect(requests, hasLength(1));
      expect(completed, isFalse);
      expect(await restoration, isNull);
      expect(store.values, isEmpty);
      expect(request!.cancelToken!.isCancelled, isTrue);
      pending!.resolve(
        Response(
          requestOptions: request!,
          data: {
            'jsonrpc': '2.0',
            'id': (request!.data as Map)['id'],
            'result': tokenResult(),
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.values, isEmpty);
      expect(requests, hasLength(1));
    },
  );
}
