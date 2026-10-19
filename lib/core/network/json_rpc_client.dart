import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/logging/app_logger.dart';

final dioProvider = Provider<Dio>((ref) {
  final configuration = ref.watch(apiConfigurationProvider);
  final dio = Dio(
    BaseOptions(
      connectTimeout: configuration.connectTimeout,
      sendTimeout: configuration.connectTimeout,
      receiveTimeout: configuration.responseTimeout,
      contentType: Headers.jsonContentType,
      headers: {'Accept': Headers.jsonContentType},
      followRedirects: false,
      maxRedirects: 0,
    ),
  );
  // Deliberately no body/header logging or automatic request retries.
  ref.onDispose(() => dio.close(force: true));
  return dio;
}, name: 'dioProvider');

final jsonRpcClientProvider = Provider<JsonRpcClient>(
  (ref) => JsonRpcClient(
    ref.watch(dioProvider),
    ref.watch(apiConfigurationProvider),
    logger: ref.watch(appLoggerProvider),
  ),
  name: 'jsonRpcClientProvider',
);

class JsonRpcClient {
  new(this._dio, this._configuration, {this._logger});

  final AppLogger? _logger;

  final Dio _dio;
  final ApiConfiguration _configuration;
  var _requestId = 0;

  Future<Map<String, dynamic>> call(
    String path, {
    Uri? backendOrigin,
    Map<String, dynamic> params = const {},
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    final id = ++_requestId;
    final timer = Stopwatch()..start();
    _logger?.event(LogEvent.rpcStarted, requestId: id);
    try {
      final result = await _call(
        path,
        id: id,
        backendOrigin: backendOrigin,
        params: params,
        accessToken: accessToken,
        cancelToken: cancelToken,
      );
      _logger?.event(
        result['ok'] == false ? LogEvent.rpcFailed : LogEvent.rpcSucceeded,
        requestId: id,
        elapsedMs: timer.elapsedMilliseconds,
      );
      return result;
    } on AppFailure catch (failure) {
      _logger?.event(
        LogEvent.rpcFailed,
        requestId: id,
        elapsedMs: timer.elapsedMilliseconds,
        failure: failure.kind,
      );
      rethrow;
    } catch (_) {
      _logger?.event(
        LogEvent.rpcFailed,
        requestId: id,
        elapsedMs: timer.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _call(
    String path, {
    required int id,
    Uri? backendOrigin,
    Map<String, dynamic> params = const {},
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    final origin = backendOrigin == null
        ? _configuration.trustedOrigin
        : _configuration.validateOrigin(backendOrigin.toString());
    if (!path.startsWith('/mupi/mobile/') ||
        path.contains('..') ||
        path.contains('?')) {
      throw invalidResponse;
    }
    try {
      final response = await _dio.postUri<Object?>(
        origin.resolve(path),
        data: {'jsonrpc': '2.0', 'method': 'call', 'params': params, 'id': id},
        options: Options(
          followRedirects: false,
          maxRedirects: 0,
          headers: {
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          },
        ),
        cancelToken: cancelToken,
      );
      final body = response.data;
      if (body is! Map<String, dynamic> ||
          body['jsonrpc'] != '2.0' ||
          body['id'] != id ||
          body.containsKey('result') == body.containsKey('error')) {
        throw invalidResponse;
      }
      if (body.containsKey('error')) {
        final error = body['error'];
        final details = error is Map ? error['data'] : null;
        final name = details is Map ? details['name'] : null;
        if (name == 'odoo.exceptions.AccessDenied' ||
            name == 'odoo.http.SessionExpiredException') {
          throw invalidSession;
        }
        if (name == 'odoo.exceptions.AccessError') {
          throw const AppFailure(
            FailureKind.forbidden,
            'You do not have permission for this operation.',
          );
        }
        throw invalidResponse;
      }
      final result = body['result'];
      if (result is! Map<String, dynamic>) throw invalidResponse;
      return result;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) throw cancelledOperation;
      if (error.response?.statusCode == 401) throw invalidSession;
      if (error.response?.statusCode == 403) {
        throw const AppFailure(
          FailureKind.forbidden,
          'You do not have permission for this operation.',
        );
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const AppFailure(
          FailureKind.timeout,
          'The server took too long to respond. Check your connection.',
        );
      }
      final status = error.response?.statusCode;
      if (status == 502 || status == 503 || status == 504) {
        throw const AppFailure(
          FailureKind.network,
          'The POS server is unavailable. Sign in with a new POS QR code.',
        );
      }
      if (status != null && status >= 300 && status < 400) {
        throw invalidResponse;
      }
      if (status != null && status >= 400) {
        throw const AppFailure(
          FailureKind.backend,
          'The Odoo server could not process this request. '
          'Contact your administrator.',
        );
      }
      throw const AppFailure(
        FailureKind.network,
        'Unable to reach the Odoo server. Check your connection.',
      );
    }
  }
}
