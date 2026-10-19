import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/logging/app_logger.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';

void main() {
  test(
    'production and nondebug builds never emit records even if requested',
    () {
      final records = <String>[];
      for (final environment in AppEnvironment.values) {
        for (final debug in [true, false]) {
          final logger = AppLogger(
            environment: environment,
            enabled: true,
            debugBuild: debug,
            sink: records.add,
          );
          records.clear();
          logger.event(LogEvent.startup);
          expect(
            records.length,
            debug && environment != AppEnvironment.production ? 1 : 0,
          );
        }
      }
      records.clear();
      AppLogger(
        environment: AppEnvironment.development,
        enabled: false,
        debugBuild: true,
        sink: records.add,
      ).event(LogEvent.startup);
      expect(records, isEmpty);
    },
  );
  test('RPC logs approved metadata without raw data', () async {
    final records = <String>[];
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final logger = AppLogger(
      environment: AppEnvironment.development,
      enabled: true,
      debugBuild: true,
      sink: records.add,
    );
    final client = JsonRpcClient(
      dio,
      const ApiConfiguration(
        baseUrl: 'https://private-host.example',
        environment: AppEnvironment.development,
      ),
      logger: logger,
    );
    var fail = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (fail) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'private-exception',
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'jsonrpc': '2.0',
                  'id': (options.data as Map)['id'],
                  'result': {'ok': true, 'token': 'private-response'},
                },
              ),
            );
          }
        },
      ),
    );
    await client.call(
      '/mupi/mobile/auth/token/check',
      accessToken: 'private-token',
      params: {'password': 'private-password', 'qr': 'private-qr'},
    );
    fail = true;
    await expectLater(
      client.call('/mupi/mobile/auth/token/check'),
      throwsException,
    );
    expect(records.join(), isNot(contains('private')));
    final decoded = records
        .map((record) => jsonDecode(record) as Map<String, dynamic>)
        .toList();
    expect(decoded.map((r) => r['event']), [
      'rpcStarted',
      'rpcSucceeded',
      'rpcStarted',
      'rpcFailed',
    ]);
    expect(decoded.map((r) => r['request_id']), [1, 1, 2, 2]);
    expect(decoded.last['failure_kind'], 'network');
    for (final record in decoded) {
      expect(
        record.keys.toSet().difference({
          'timestamp',
          'environment',
          'event',
          'request_id',
          'elapsed_ms',
          'failure_kind',
        }),
        isEmpty,
      );
    }
  });
}
