import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';

class _Reporter extends NoopCrashReporter {
  new();

  final operations = <String>[];

  @override
  String? recordFailure(
    AppFailure failure, {
    required String operation,
    StackTrace? stack,
  }) {
    operations.add(operation);
    return 'OO-ABCDEF';
  }
}

class _Adapter implements HttpClientAdapter {
  new(this.status, this.body);

  final int status;
  final Map<String, Object?> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  const apiBase = 'https://pos.example/api/orangeone/mobile/v1';

  Future<AppFailure> failWith(
    int status,
    String code,
    _Reporter reporter, {
    String path = '/products/42/stock-adjustments',
  }) async {
    final dio = Dio(BaseOptions(contentType: Headers.jsonContentType))
      ..httpClientAdapter = _Adapter(status, {
        'error': {'code': code, 'message': 'Server detail', 'retryable': false},
        'meta': {'request_id': 'server-request-9'},
      });
    addTearDown(() => dio.close(force: true));
    final client = MobileApiClient(
      dio,
      const ApiConfiguration(
        baseUrl: 'https://fallback.example',
        environment: AppEnvironment.development,
      ),
      crashReporter: reporter,
    );
    try {
      await client.send(
        MobileApiMethod.post,
        path,
        apiBase: Uri.parse(apiBase),
        accessToken: 'oa_fixture',
      );
    } on AppFailure catch (failure) {
      return failure;
    }
    throw StateError('expected a failure');
  }

  test(
    'a technical failure carries the reference and the request id',
    () async {
      final reporter = _Reporter();
      final failure = await failWith(500, 'INTERNAL_ERROR', reporter);
      expect(failure.errorReference, 'OO-ABCDEF');
      expect(failure.message, endsWith('(Ref: OO-ABCDEF)'));
      expect(failure.requestId, 'server-request-9');
      expect(failure.code, 'INTERNAL_ERROR');
      expect(failure.kind, FailureKind.backend);
      expect(reporter.operations, ['POST /products/{id}/stock-adjustments']);
    },
  );

  test('operation labels never contain barcodes or ids', () async {
    final reporter = _Reporter();
    await failWith(
      500,
      'INTERNAL_ERROR',
      reporter,
      path: '/products/by-barcode/7612345678900',
    );
    expect(reporter.operations.single, 'POST /products/by-barcode/{id}');
  });

  test('without a reporter the failure is unchanged', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(500, {
        'error': {'code': 'INTERNAL_ERROR', 'message': 'Server detail'},
        'meta': {'request_id': 'r'},
      });
    addTearDown(() => dio.close(force: true));
    final client = MobileApiClient(
      dio,
      const ApiConfiguration(
        baseUrl: 'https://fallback.example',
        environment: AppEnvironment.development,
      ),
    );
    await expectLater(
      client.send(MobileApiMethod.get, '/session', apiBase: Uri.parse(apiBase)),
      throwsA(
        isA<AppFailure>()
            .having((f) => f.errorReference, 'reference', isNull)
            .having((f) => f.message, 'message', 'Server detail'),
      ),
    );
  });
}
