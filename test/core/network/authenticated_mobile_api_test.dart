import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/features/authentication/data/data_sources/auth_remote_data_source.dart';
import 'package:orange_one/features/authentication/data/repositories/odoo_auth_repository.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';

class _Tokens implements AccessTokenSource {
  String current = 'oa_1';
  String next = 'oa_2';
  final refreshed = <String>[];

  @override
  Future<String> accessToken() async => current;

  @override
  Future<String> refreshAccessToken(String rejectedToken) async {
    refreshed.add(rejectedToken);
    return current = next;
  }
}

/// Adapts the real repository, as app composition does with the controller.
class _RepositoryTokens implements AccessTokenSource {
  const new(this._repository);
  final OdooAuthRepository _repository;

  @override
  Future<String> accessToken() => _repository.accessToken();

  @override
  Future<String> refreshAccessToken(String rejectedToken) =>
      _repository.refreshAccessToken(rejectedToken);
}

void main() {
  const config = ApiConfiguration(
    baseUrl: '',
    environment: AppEnvironment.development,
  );
  late Dio dio;
  late FakeMobileApiServer server;
  late _Tokens tokens;
  late AuthenticatedMobileApi api;

  setUp(() {
    dio = Dio();
    server = FakeMobileApiServer();
    dio.httpClientAdapter = server;
    tokens = _Tokens();
    api = AuthenticatedMobileApi(
      MobileApiClient(dio, config),
      apiBase: testApiBase,
      tokens: tokens,
    );
  });
  tearDown(() => dio.close(force: true));

  test('sends the current token to the session API base', () async {
    server.on('GET /products/7', (_) => FakeReply(200, successEnvelope({})));

    await api.send(MobileApiMethod.get, '/products/7');

    final request = server.requests.single;
    expect(request.uri.toString(), '$testApiBase/products/7');
    expect(request.headers['Authorization'], 'Bearer oa_1');
    expect(tokens.refreshed, isEmpty);
  });

  test(
    'refreshes once on TOKEN_EXPIRED and repeats the same request',
    () async {
      server.on(
        'PUT /products/7/price',
        (request) => request.headers['Authorization'] == 'Bearer oa_1'
            ? FakeReply(401, errorEnvelope('TOKEN_EXPIRED'))
            : FakeReply(200, successEnvelope({'id': 7})),
      );

      final response = await api.send(
        MobileApiMethod.put,
        '/products/7/price',
        body: {'list_price': '12.00'},
        idempotencyKey: '7f1c0c6e-58b1-4a5d-9b7b-0d1f6c3f0a11',
        ifMatchVersion: 'v1',
      );

      expect(response.data, {'id': 7});
      expect(tokens.refreshed, ['oa_1']);
      final [first, second] = server.requests;
      expect(second.headers['Authorization'], 'Bearer oa_2');
      expect(second.data, first.data);
      expect(
        second.headers['Idempotency-Key'],
        first.headers['Idempotency-Key'],
      );
      expect(second.headers['If-Match'], first.headers['If-Match']);
    },
  );

  test('does not refresh again when the new token is also rejected', () async {
    server.on(
      'GET /auth/session',
      (_) => FakeReply(401, errorEnvelope('TOKEN_EXPIRED')),
    );

    await expectLater(
      api.send(MobileApiMethod.get, '/auth/session'),
      throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'TOKEN_EXPIRED')),
    );
    expect(server.requests, hasLength(2));
    expect(tokens.refreshed, hasLength(1));
  });

  for (final code in ['TOKEN_REVOKED', 'TOKEN_INVALID', 'PERMISSION_DENIED']) {
    test('does not retry $code', () async {
      server.on('GET /products/7', (_) => FakeReply(401, errorEnvelope(code)));

      await expectLater(
        api.send(MobileApiMethod.get, '/products/7'),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', code)),
      );
      expect(server.requests, hasLength(1));
      expect(tokens.refreshed, isEmpty);
    });
  }

  test('concurrent requests share one refresh of an expired token', () async {
    var now = testNow;
    final repository = OdooAuthRepository(
      AuthRemoteDataSource(MobileApiClient(dio, config)),
      MemorySecretStore(),
      config,
      () => now,
      platform: 'android',
      appVersion: '1.0.0',
    );
    addTearDown(repository.dispose);
    server
      ..on(
        'POST /auth/qr-exchange',
        (_) => FakeReply(200, successEnvelope(tokenGrant())),
      )
      ..on(
        'POST /auth/token/refresh',
        (_) => FakeReply(200, successEnvelope(tokenGrant(access: 'oa_new'))),
      )
      ..on(
        'GET /products/7',
        (request) => request.headers['Authorization'] == 'Bearer oa_new'
            ? FakeReply(200, successEnvelope({'id': 7}))
            : FakeReply(401, errorEnvelope('TOKEN_EXPIRED')),
      );
    await repository.signIn(validQr());
    api = AuthenticatedMobileApi(
      MobileApiClient(dio, config),
      apiBase: testApiBase,
      tokens: _RepositoryTokens(repository),
    );
    now = testNow.add(const Duration(minutes: 20));

    final responses = await Future.wait([
      for (var i = 0; i < 3; i++) api.send(MobileApiMethod.get, '/products/7'),
    ]);

    expect(responses.map((response) => response.data), everyElement({'id': 7}));
    expect(server.called('POST /auth/token/refresh'), hasLength(1));
    expect(
      server.called('GET /products/7').map((r) => r.headers['Authorization']),
      everyElement('Bearer oa_new'),
    );
  });
}
