import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';

void main() {
  late Dio dio;
  late JsonRpcClient client;
  setUp(() {
    dio = Dio();
    client = JsonRpcClient(
      dio,
      const ApiConfiguration(
        baseUrl: 'https://pos.example',
        environment: AppEnvironment.production,
      ),
    );
  });
  tearDown(() => dio.close(force: true));

  for (final entry in {
    401: FailureKind.unauthenticated,
    403: FailureKind.forbidden,
    500: FailureKind.backend,
    502: FailureKind.network,
    503: FailureKind.network,
    504: FailureKind.network,
    302: FailureKind.protocol,
  }.entries) {
    test('maps HTTP ${entry.key} independently from JSON-RPC errors', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: entry.key,
                ),
              ),
            );
          },
        ),
      );
      await expectLater(
        client.call('/mupi/mobile/auth/token/check'),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', entry.value)),
      );
    });
  }

  test(
    'uses named params, matching sequential IDs and per-request bearer auth',
    () async {
      final requests = <RequestOptions>[];
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
                  'result': {'ok': true},
                },
              ),
            );
          },
        ),
      );
      await client.call(
        '/mupi/mobile/auth/token/check',
        accessToken: 'fixture',
      );
      await client.call(
        '/mupi/mobile/auth/challenge/validate',
        params: {'challenge': 'fixture'},
      );
      expect((requests[0].data as Map)['method'], 'call');
      expect((requests[0].data as Map)['params'], isEmpty);
      expect((requests[0].data as Map)['id'], 1);
      expect((requests[1].data as Map)['id'], 2);
      expect(requests[0].headers['Authorization'], 'Bearer fixture');
      expect(requests[1].headers.containsKey('Authorization'), isFalse);
      expect(dio.options.headers.containsKey('Authorization'), isFalse);
    },
  );

  for (final response in <Object?>[
    null,
    '<html>login</html>',
    [],
    {'ok': true},
    {'jsonrpc': '2.0', 'id': 999, 'result': <String, dynamic>{}},
    {'jsonrpc': '2.0', 'id': 1, 'result': <Object?>[]},
    {
      'jsonrpc': '2.0',
      'id': 1,
      'result': <String, dynamic>{},
      'error': <String, dynamic>{},
    },
    {
      'jsonrpc': '2.0',
      'id': 1,
      'error': {'code': 200, 'message': 'private server trace'},
    },
  ]) {
    test(
      'rejects malformed/protocol response ${response.runtimeType}',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(requestOptions: options, data: response),
              );
            },
          ),
        );
        await expectLater(
          client.call('/mupi/mobile/auth/token/check'),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.protocol,
            ),
          ),
        );
      },
    );
  }

  for (final entry in {
    'odoo.exceptions.AccessDenied': FailureKind.unauthenticated,
    'odoo.exceptions.AccessError': FailureKind.forbidden,
  }.entries) {
    test('maps JSON-RPC ${entry.key} separately', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'jsonrpc': '2.0',
                  'id': 1,
                  'error': {
                    'data': {'name': entry.key},
                  },
                },
              ),
            );
          },
        ),
      );
      await expectLater(
        client.call('/mupi/mobile/auth/token/check'),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', entry.value)),
      );
    });
  }

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.cancel,
  ]) {
    test('maps $type without raw request details', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: type,
                message: 'private authentication details',
              ),
            );
          },
        ),
      );
      await expectLater(
        client.call('/mupi/mobile/auth/token/check'),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message.contains('private'),
            'safe message',
            isFalse,
          ),
        ),
      );
    });
  }
}
