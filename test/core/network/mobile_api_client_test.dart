import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/logging/app_logger.dart';
import 'package:orange_one/core/network/dio_provider.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';

/// Answers every request with a scripted HTTP response, through Dio's real
/// status validation and JSON transformer.
class _FakeAdapter implements HttpClientAdapter {
  new(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  int status,
  Object? body, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  body == null ? '' : jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

Map<String, dynamic> _error(
  String code, {
  String message = 'Localized server message.',
  bool retryable = false,
  List<Object?>? details,
}) => {
  'error': {
    'code': code,
    'message': message,
    'retryable': retryable,
    'details': ?details,
  },
  'meta': {'request_id': 'server-request-1', 'api_version': '1.0.0'},
};

const _apiBase = 'https://pos.example/api/orangeone/mobile/v1';

void main() {
  late Dio dio;
  late _FakeAdapter adapter;
  late MobileApiClient client;
  late List<String> logs;

  void serve(ResponseBody Function(RequestOptions options) respond) {
    adapter = _FakeAdapter(respond);
    dio.httpClientAdapter = adapter;
  }

  setUp(() {
    dio = Dio(BaseOptions(contentType: Headers.jsonContentType));
    logs = [];
    client = MobileApiClient(
      dio,
      const ApiConfiguration(
        baseUrl: 'https://fallback.example',
        environment: AppEnvironment.development,
      ),
      logger: AppLogger(
        environment: AppEnvironment.development,
        enabled: true,
        debugBuild: true,
        sink: logs.add,
      ),
    );
    serve(
      (_) => _json(200, {
        'data': {'ok': true},
        'meta': {'request_id': 'server-request-1'},
      }),
    );
  });
  tearDown(() => dio.close(force: true));

  group('requests', () {
    test('build the contract URL, method, body and headers', () async {
      await client.send(
        MobileApiMethod.patch,
        '/products/7',
        apiBase: Uri.parse(
          'http://192.168.1.2:8069/odoo/api/orangeone/mobile/v1',
        ),
        body: {'name': 'Masala'},
        query: {'q': 'a b'},
        accessToken: 'oa_fixture',
        language: 'de-CH',
        idempotencyKey: '7f1c0c6e-58b1-4a5d-9b7b-0d1f6c3f0a11',
        ifMatchVersion: 'abc123',
        ifNoneMatch: '"etag-1"',
      );

      final request = adapter.requests.single;
      expect(request.method, 'PATCH');
      expect(
        request.uri.toString(),
        'http://192.168.1.2:8069/odoo/api/orangeone/mobile/v1/products/7?q=a+b',
      );
      expect(request.data, {'name': 'Masala'});
      expect(request.headers['Authorization'], 'Bearer oa_fixture');
      expect(request.headers['Accept-Language'], 'de-CH');
      expect(
        request.headers['Idempotency-Key'],
        '7f1c0c6e-58b1-4a5d-9b7b-0d1f6c3f0a11',
      );
      expect(request.headers['If-Match'], '"abc123"');
      expect(request.headers['If-None-Match'], '"etag-1"');
      expect(
        request.headers['X-Request-Id'],
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
      expect(request.followRedirects, isFalse);
      expect(dio.options.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'send X-App-Version on every request when a version is known',
      () async {
        final versioned = MobileApiClient(
          dio,
          const ApiConfiguration(
            baseUrl: 'https://fallback.example',
            environment: AppEnvironment.development,
          ),
          appVersion: '1.2.3',
        );
        await versioned.send(
          MobileApiMethod.post,
          '/auth/qr-exchange',
          apiBase: Uri.parse(_apiBase),
        );
        await versioned.send(
          MobileApiMethod.get,
          '/products',
          apiBase: Uri.parse(_apiBase),
          accessToken: 'oa_fixture',
        );
        expect(
          [for (final r in adapter.requests) r.headers['X-App-Version']],
          ['1.2.3', '1.2.3'],
        );
      },
    );

    test('omit optional headers and use a fresh request id per call', () async {
      await client.send(
        MobileApiMethod.get,
        '/meta',
        apiBase: Uri.parse(_apiBase),
      );
      await client.send(
        MobileApiMethod.get,
        '/meta',
        apiBase: Uri.parse(_apiBase),
      );

      final [first, second] = adapter.requests;
      for (final header in [
        'Authorization',
        'Accept-Language',
        'Idempotency-Key',
        'If-Match',
        'If-None-Match',
        'X-App-Version',
      ]) {
        expect(first.headers.containsKey(header), isFalse, reason: header);
      }
      expect(first.method, 'GET');
      expect(
        first.headers['X-Request-Id'],
        isNot(second.headers['X-Request-Id']),
      );
    });

    test(
      'fall back to the configured origin when no API base is given',
      () async {
        await client.send(MobileApiMethod.get, '/meta');

        expect(
          adapter.requests.single.uri.toString(),
          'https://fallback.example/api/orangeone/mobile/v1/meta',
        );
      },
    );

    test('encoded path segments stay encoded', () async {
      await client.send(
        MobileApiMethod.get,
        '/products/by-barcode/${Uri.encodeComponent('A/B 1')}',
        apiBase: Uri.parse(_apiBase),
      );

      expect(
        adapter.requests.single.uri.path,
        '/api/orangeone/mobile/v1/products/by-barcode/A%2FB%201',
      );
    });

    for (final path in [
      'meta',
      '/a/../meta',
      '/a?x=1',
      '/a#x',
      '//evil.example/x',
    ]) {
      test('reject the unsafe path "$path" before sending', () async {
        await expectLater(
          client.send(MobileApiMethod.get, path, apiBase: Uri.parse(_apiBase)),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.protocol,
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
      });
    }

    for (final base in [
      'https://pos.example',
      'https://pos.example/api/orangeone/mobile/v2',
      'ftp://pos.example$_apiBase',
      'https://pos.example$_apiBase?db=other',
    ]) {
      test('reject the API base $base before sending', () async {
        await expectLater(
          client.send(MobileApiMethod.get, '/meta', apiBase: Uri.parse(base)),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.unsupportedQr,
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
      });
    }
  });

  group('success responses', () {
    test('parse data, meta and representation headers', () async {
      serve(
        (_) => _json(
          201,
          {
            'data': {'id': 7},
            'meta': {
              'request_id': 'r-201',
              'server_time': '2026-10-27T08:00:00Z',
            },
          },
          headers: {
            'etag': ['"etag-7"'],
            'location': ['/api/orangeone/mobile/v1/products/7'],
            'idempotent-replayed': ['true'],
          },
        ),
      );

      final response = await client.send(
        MobileApiMethod.post,
        '/products',
        apiBase: Uri.parse(_apiBase),
        body: const {},
      );

      expect(response.statusCode, 201);
      expect(response.data, {'id': 7});
      expect(response.requestId, 'r-201');
      expect(response.meta['server_time'], '2026-10-27T08:00:00Z');
      expect(response.etag, '"etag-7"');
      expect(response.location, '/api/orangeone/mobile/v1/products/7');
      expect(response.replayed, isTrue);
      expect(response.notModified, isFalse);
    });

    test('keep list data and pagination meta', () async {
      serve(
        (_) => _json(200, {
          'data': [
            {'id': 1},
          ],
          'meta': {'request_id': 'r', 'next_cursor': 'Mg'},
        }),
      );

      final response = await client.send(
        MobileApiMethod.get,
        '/products',
        apiBase: Uri.parse(_apiBase),
      );

      expect(response.data, [
        {'id': 1},
      ]);
      expect(response.meta['next_cursor'], 'Mg');
    });

    for (final status in [204, 304]) {
      test('accept an empty $status response', () async {
        serve(
          (_) => _json(
            status,
            null,
            headers: {
              'etag': ['"etag-7"'],
            },
          ),
        );

        final response = await client.send(
          MobileApiMethod.get,
          '/products/7',
          apiBase: Uri.parse(_apiBase),
        );

        expect(response.statusCode, status);
        expect(response.data, isNull);
        expect(response.notModified, status == 304);
        expect(response.etag, '"etag-7"');
      });
    }

    for (final body in <Object?>[
      null,
      '<html>login</html>',
      <Object?>[],
      {'data': <String, dynamic>{}},
      {'data': <String, dynamic>{}, 'meta': 'x'},
      {'meta': <String, dynamic>{}},
      {
        'data': <String, dynamic>{},
        'meta': <String, dynamic>{},
        'error': {'code': 'INTERNAL_ERROR'},
      },
    ]) {
      test('reject the malformed 200 body $body', () async {
        serve(
          (_) => body is String
              ? ResponseBody.fromString(
                  body,
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['text/html'],
                  },
                )
              : _json(200, body),
        );

        await expectLater(
          client.send(
            MobileApiMethod.get,
            '/meta',
            apiBase: Uri.parse(_apiBase),
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.protocol,
            ),
          ),
        );
      });
    }
  });

  group('error envelopes', () {
    const kinds = <String, (int, FailureKind)>{
      'MALFORMED_REQUEST': (400, FailureKind.protocol),
      'VALIDATION_FAILED': (400, FailureKind.validation),
      'AUTH_REQUIRED': (401, FailureKind.unauthenticated),
      'TOKEN_EXPIRED': (401, FailureKind.unauthenticated),
      'TOKEN_REVOKED': (401, FailureKind.unauthenticated),
      'TOKEN_INVALID': (401, FailureKind.unauthenticated),
      'QR_INVALID': (401, FailureKind.validation),
      'QR_EXPIRED': (401, FailureKind.expiredQr),
      'QR_USED': (401, FailureKind.usedQr),
      'PERMISSION_DENIED': (403, FailureKind.forbidden),
      'COMPANY_MISMATCH': (403, FailureKind.forbidden),
      'DEVICE_MISMATCH': (403, FailureKind.forbidden),
      'NOT_FOUND': (404, FailureKind.notFound),
      'PRODUCT_NOT_FOUND': (404, FailureKind.notFound),
      'BARCODE_EXISTS': (409, FailureKind.conflict),
      'CATEGORY_EXISTS': (409, FailureKind.conflict),
      'IDEMPOTENCY_KEY_REUSED': (409, FailureKind.conflict),
      'SYNC_TOKEN_EXPIRED': (410, FailureKind.conflict),
      'VERSION_CONFLICT': (412, FailureKind.conflict),
      'BUSINESS_RULE_VIOLATION': (422, FailureKind.validation),
      'APP_UPGRADE_REQUIRED': (426, FailureKind.upgradeRequired),
      'PRECONDITION_REQUIRED': (428, FailureKind.protocol),
      'RATE_LIMITED': (429, FailureKind.rateLimited),
      'INTERNAL_ERROR': (500, FailureKind.backend),
      'MAINTENANCE': (503, FailureKind.network),
      'SERVICE_UNAVAILABLE': (503, FailureKind.network),
    };

    for (final MapEntry(key: code, value: (status, kind)) in kinds.entries) {
      test('map $code ($status) to ${kind.name}', () async {
        serve((_) => _json(status, _error(code)));

        await expectLater(
          client.send(
            MobileApiMethod.get,
            '/meta',
            apiBase: Uri.parse(_apiBase),
          ),
          throwsA(
            isA<AppFailure>()
                .having((e) => e.kind, 'kind', kind)
                .having((e) => e.code, 'code', code)
                .having(
                  (e) => e.message,
                  'message',
                  'Localized server message.',
                )
                .having((e) => e.requestId, 'requestId', 'server-request-1'),
          ),
        );
      });
    }

    test('keep field errors, retry hints and unknown codes safe', () async {
      serve(
        (_) => _json(
          429,
          _error(
            'NEW_FUTURE_CODE',
            retryable: true,
            details: [
              {
                'field': 'list_price',
                'code': 'INVALID_DECIMAL',
                'message': 'x',
              },
              {
                'current': {'id': 7},
              },
              'ignored',
            ],
          ),
          headers: {
            'retry-after': ['17'],
          },
        ),
      );

      final failure = await client
          .send(MobileApiMethod.get, '/meta', apiBase: Uri.parse(_apiBase))
          .then<AppFailure?>(
            (_) => null,
            onError: (Object e) => e as AppFailure,
          );

      expect(failure!.kind, FailureKind.backend);
      expect(failure.code, 'NEW_FUTURE_CODE');
      expect(failure.retryable, isTrue);
      expect(failure.retryAfter, const Duration(seconds: 17));
      expect(failure.fieldErrors.single.field, 'list_price');
      expect(failure.fieldErrors.single.code, 'INVALID_DECIMAL');
    });

    for (final message in ['', '   ', 'x' * 501]) {
      test('use a safe fallback for an unusable message', () async {
        serve((_) => _json(403, _error('PERMISSION_DENIED', message: message)));

        await expectLater(
          client.send(
            MobileApiMethod.get,
            '/meta',
            apiBase: Uri.parse(_apiBase),
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              'You do not have permission for this operation.',
            ),
          ),
        );
      });
    }
  });

  group('responses without an error envelope', () {
    const statuses = <int, FailureKind>{
      302: FailureKind.protocol,
      400: FailureKind.backend,
      401: FailureKind.unauthenticated,
      403: FailureKind.forbidden,
      404: FailureKind.backend,
      500: FailureKind.backend,
      502: FailureKind.network,
      503: FailureKind.network,
      504: FailureKind.network,
    };

    for (final MapEntry(key: status, value: kind) in statuses.entries) {
      test('map HTTP $status to ${kind.name}', () async {
        serve(
          (_) => ResponseBody.fromString(
            '<html>private proxy page</html>',
            status,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
              'location': ['https://elsewhere.example'],
            },
          ),
        );

        await expectLater(
          client.send(
            MobileApiMethod.get,
            '/meta',
            apiBase: Uri.parse(_apiBase),
          ),
          throwsA(
            isA<AppFailure>()
                .having((e) => e.kind, 'kind', kind)
                .having((e) => e.message.contains('private'), 'safe', isFalse),
          ),
        );
      });
    }
  });

  group('transport failures', () {
    const types = <DioExceptionType, FailureKind>{
      DioExceptionType.connectionError: FailureKind.network,
      DioExceptionType.badCertificate: FailureKind.network,
      DioExceptionType.unknown: FailureKind.network,
      DioExceptionType.connectionTimeout: FailureKind.timeout,
      DioExceptionType.sendTimeout: FailureKind.timeout,
      DioExceptionType.receiveTimeout: FailureKind.timeout,
      DioExceptionType.cancel: FailureKind.cancelled,
    };

    for (final MapEntry(key: type, value: kind) in types.entries) {
      test('map $type to ${kind.name} without raw details', () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
              DioException(
                requestOptions: options,
                type: type,
                message: 'private authentication details',
              ),
            ),
          ),
        );

        await expectLater(
          client.send(
            MobileApiMethod.get,
            '/meta',
            apiBase: Uri.parse(_apiBase),
          ),
          throwsA(
            isA<AppFailure>()
                .having((e) => e.kind, 'kind', kind)
                .having((e) => e.message.contains('private'), 'safe', isFalse),
          ),
        );
      });
    }
  });

  test('logs fixed events without tokens, URLs or bodies', () async {
    await client.send(
      MobileApiMethod.post,
      '/auth/logout',
      apiBase: Uri.parse(_apiBase),
      accessToken: 'oa_secret_token',
      body: const {'nonce': 'secret-nonce'},
    );
    serve((_) => _json(401, _error('TOKEN_REVOKED')));
    await expectLater(
      client.send(
        MobileApiMethod.get,
        '/auth/session',
        apiBase: Uri.parse(_apiBase),
        accessToken: 'oa_secret_token',
      ),
      throwsA(isA<AppFailure>()),
    );

    expect(logs, hasLength(4));
    expect(logs.last, contains('"failure_kind":"unauthenticated"'));
    for (final record in logs) {
      expect(record, isNot(contains('secret')));
      expect(record, isNot(contains('pos.example')));
      expect(record, isNot(contains('server-request-1')));
    }
  });

  test('provider shares the flavor-configured Dio and timeouts', () {
    final container = ProviderContainer.test(
      overrides: [
        apiConfigurationProvider.overrideWithValue(
          const ApiConfiguration(
            baseUrl: '',
            environment: AppEnvironment.staging,
            connectTimeout: Duration(seconds: 3),
            responseTimeout: Duration(seconds: 9),
          ),
        ),
        appLoggerProvider.overrideWithValue(
          AppLogger(
            environment: AppEnvironment.staging,
            enabled: false,
            debugBuild: false,
          ),
        ),
      ],
    );

    expect(container.read(mobileApiClientProvider), isA<MobileApiClient>());
    final shared = container.read(dioProvider);
    expect(shared.options.connectTimeout, const Duration(seconds: 3));
    expect(shared.options.receiveTimeout, const Duration(seconds: 9));
    expect(shared.options.followRedirects, isFalse);
  });
}
