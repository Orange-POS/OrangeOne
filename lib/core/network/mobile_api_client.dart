import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_version.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/logging/app_logger.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/monitoring/reportable_failure.dart';
import 'package:orange_one/core/network/dio_provider.dart';

final mobileApiClientProvider = Provider<MobileApiClient>(
  (ref) => MobileApiClient(
    ref.watch(dioProvider),
    ref.watch(apiConfigurationProvider),
    logger: ref.watch(appLoggerProvider),
    appVersion: ref.watch(appVersionProvider),
    crashReporter: ref.watch(crashReporterProvider),
  ),
  name: 'mobileApiClientProvider',
);

/// HTTP methods used by the Mobile API v2 contract.
enum MobileApiMethod { get, post, put, patch }

/// Parsed `SuccessEnvelope` (or an empty 204/304 response).
class MobileApiResponse {
  const new({
    required this.statusCode,
    required this.data,
    this.meta = const {},
    this.etag,
    this.location,
    this.replayed = false,
  });

  final int statusCode;

  /// `data` of the envelope; `null` for 204 and 304 responses.
  final Object? data;

  /// `meta` of the envelope (request_id, server_time, api_version, cursors).
  final Map<String, dynamic> meta;
  final String? etag;
  final String? location;

  /// True when the server replayed a stored idempotent response.
  final bool replayed;

  bool get notModified => statusCode == 304;
  String? get requestId {
    final value = meta['request_id'];
    return value is String ? value : null;
  }
}

/// REST client for the OrangeONE Mobile API v2 (`openapi.yaml`).
///
/// It shares the configured [Dio] (timeouts, no redirects, no body logging)
/// with every API call. Callers pass the per-session API base and
/// bearer token on each request, so token refresh can be added around this
/// client without rebuilding it.
class MobileApiClient {
  new(
    this._dio,
    this._configuration, {
    this._logger,
    this._appVersion,
    this._crashReporter,
  });

  final Dio _dio;
  final ApiConfiguration _configuration;
  final AppLogger? _logger;

  /// Reports technical failures (never expected business outcomes).
  final CrashReporter? _crashReporter;

  /// Sent as `X-App-Version` on every request: the backend's minimum-version
  /// gate reads this header (not `device.app_version`). Null sends none.
  final String? _appVersion;
  final _random = Random.secure();
  var _requestCount = 0;

  static const _maxMessageLength = 500;

  Future<MobileApiResponse> send(
    MobileApiMethod method,
    String path, {
    Uri? apiBase,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? accessToken,
    String? language,
    String? idempotencyKey,
    String? ifMatchVersion,
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) async {
    final id = ++_requestCount;
    final timer = Stopwatch()..start();
    _logger?.event(LogEvent.rpcStarted, requestId: id);
    try {
      final response = await _send(
        method,
        path,
        apiBase: apiBase,
        body: body,
        query: query,
        accessToken: accessToken,
        language: language,
        idempotencyKey: idempotencyKey,
        ifMatchVersion: ifMatchVersion,
        ifNoneMatch: ifNoneMatch,
        cancelToken: cancelToken,
      );
      _logger?.event(
        LogEvent.rpcSucceeded,
        requestId: id,
        elapsedMs: timer.elapsedMilliseconds,
      );
      return response;
    } on AppFailure catch (failure) {
      _logger?.event(
        LogEvent.rpcFailed,
        requestId: id,
        elapsedMs: timer.elapsedMilliseconds,
        failure: failure.kind,
      );
      final reference = _crashReporter?.recordFailure(
        failure,
        operation: operationLabel(method.name, path),
      );
      if (reference != null) throw failure.withReference(reference);
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

  Future<MobileApiResponse> _send(
    MobileApiMethod method,
    String path, {
    required Uri? apiBase,
    required Map<String, dynamic>? body,
    required Map<String, String>? query,
    required String? accessToken,
    required String? language,
    required String? idempotencyKey,
    required String? ifMatchVersion,
    required String? ifNoneMatch,
    required CancelToken? cancelToken,
  }) async {
    final base = apiBase == null
        ? _configuration.trustedApiBase
        : _configuration.validateApiBase(apiBase.toString());
    if (!path.startsWith('/') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains('//') ||
        path.split('/').any((segment) => segment == '..' || segment == '.')) {
      throw invalidResponse;
    }
    final uri = base.replace(
      path: '${base.path}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final headers = <String, String>{
      'X-Request-Id': _newRequestId(),
      'X-App-Version': ?_appVersion,
      'Authorization': ?(accessToken == null ? null : 'Bearer $accessToken'),
      'Accept-Language': ?language,
      'Idempotency-Key': ?idempotencyKey,
      'If-Match': ?(ifMatchVersion == null ? null : '"$ifMatchVersion"'),
      'If-None-Match': ?ifNoneMatch,
    };
    try {
      final response = await _dio.requestUri<Object?>(
        uri,
        data: body,
        options: Options(
          method: method.name.toUpperCase(),
          headers: headers,
          followRedirects: false,
          maxRedirects: 0,
          // Status codes are part of the contract and handled below.
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );
      return _parse(response);
    } on DioException catch (error) {
      throw _transportFailure(error);
    }
  }

  MobileApiResponse _parse(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    final body = response.data;
    final requestId = _requestIdOf(body);

    if (status == 204 || status == 304) {
      return MobileApiResponse(
        statusCode: status,
        data: null,
        meta: requestId == null ? const {} : {'request_id': requestId},
        etag: response.headers.value('etag'),
        location: response.headers.value('location'),
        replayed: response.headers.value('idempotent-replayed') == 'true',
      );
    }
    if (status >= 200 && status < 300) {
      if (body is! Map<String, dynamic> ||
          !body.containsKey('data') ||
          body.containsKey('error') ||
          body['meta'] is! Map<String, dynamic>) {
        throw invalidResponse;
      }
      return MobileApiResponse(
        statusCode: status,
        data: body['data'],
        meta: body['meta'] as Map<String, dynamic>,
        etag: response.headers.value('etag'),
        location: response.headers.value('location'),
        replayed: response.headers.value('idempotent-replayed') == 'true',
      );
    }
    final error = body is Map<String, dynamic> ? body['error'] : null;
    if (error is Map<String, dynamic> && error['code'] is String) {
      throw _apiFailure(
        error,
        requestId: requestId,
        retryAfter: _retryAfter(response.headers.value('retry-after')),
      );
    }
    throw _statusFailure(status);
  }

  AppFailure _apiFailure(
    Map<String, dynamic> error, {
    required String? requestId,
    required Duration? retryAfter,
  }) {
    final code = error['code'] as String;
    final kind = _kinds[code] ?? FailureKind.backend;
    final serverMessage = _text(error['message'])?.trim();
    final details = error['details'];
    return AppFailure(
      kind,
      serverMessage != null &&
              serverMessage.isNotEmpty &&
              serverMessage.length <= _maxMessageLength
          ? serverMessage
          : _fallbackMessages[kind] ?? _fallbackMessages[FailureKind.backend]!,
      code: code,
      fieldErrors: [
        if (details is List)
          for (final detail in details)
            if (detail is Map<String, dynamic> &&
                detail['field'] is String &&
                detail['code'] is String)
              AppFieldError(
                detail['field'] as String,
                detail['code'] as String,
              ),
      ],
      retryable: error['retryable'] == true,
      retryAfter: retryAfter,
      requestId: requestId,
    );
  }

  /// Responses without an error envelope, such as a proxy error page.
  AppFailure _statusFailure(int status) {
    if (status >= 300 && status < 400) return invalidResponse;
    if (status == 401) return invalidSession;
    if (status == 403) {
      return AppFailure(
        FailureKind.forbidden,
        _fallbackMessages[FailureKind.forbidden]!,
      );
    }
    if (status == 502 || status == 503 || status == 504) {
      return const AppFailure(
        FailureKind.network,
        'The POS server is unavailable. Try again shortly.',
        retryable: true,
      );
    }
    if (status >= 400) {
      return AppFailure(
        FailureKind.backend,
        _fallbackMessages[FailureKind.backend]!,
      );
    }
    return invalidResponse;
  }

  AppFailure _transportFailure(DioException error) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return cancelledOperation;
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const AppFailure(
          FailureKind.timeout,
          'The server took too long to respond. Check your connection.',
          retryable: true,
        );
      case DioExceptionType.badResponse:
        return _statusFailure(error.response?.statusCode ?? 0);
      case DioExceptionType.badCertificate:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const AppFailure(
          FailureKind.network,
          'Unable to reach the server. Check your connection.',
          retryable: true,
        );
    }
  }

  String _newRequestId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String? _requestIdOf(Object? body) {
    if (body is! Map<String, dynamic>) return null;
    final meta = body['meta'];
    return meta is Map<String, dynamic> ? _text(meta['request_id']) : null;
  }

  static Duration? _retryAfter(String? value) {
    final seconds = value == null ? null : int.tryParse(value.trim());
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  static String? _text(Object? value) => value is String ? value : null;

  /// `ErrorCode` values of the contract. Unknown codes are backend failures.
  /// Maintenance and service outages map to [FailureKind.network] so callers
  /// keep their existing offline fallback behavior.
  static const _kinds = <String, FailureKind>{
    'MALFORMED_REQUEST': FailureKind.protocol,
    'VALIDATION_FAILED': FailureKind.validation,
    'AUTH_REQUIRED': FailureKind.unauthenticated,
    'TOKEN_EXPIRED': FailureKind.unauthenticated,
    'TOKEN_REVOKED': FailureKind.unauthenticated,
    'TOKEN_INVALID': FailureKind.unauthenticated,
    'QR_INVALID': FailureKind.validation,
    'QR_EXPIRED': FailureKind.expiredQr,
    'QR_USED': FailureKind.usedQr,
    'PERMISSION_DENIED': FailureKind.forbidden,
    'COMPANY_MISMATCH': FailureKind.forbidden,
    'DEVICE_MISMATCH': FailureKind.forbidden,
    'NOT_FOUND': FailureKind.notFound,
    'PRODUCT_NOT_FOUND': FailureKind.notFound,
    'BARCODE_EXISTS': FailureKind.conflict,
    'CATEGORY_EXISTS': FailureKind.conflict,
    'IDEMPOTENCY_KEY_REUSED': FailureKind.conflict,
    'VERSION_CONFLICT': FailureKind.conflict,
    'PRECONDITION_REQUIRED': FailureKind.protocol,
    'BUSINESS_RULE_VIOLATION': FailureKind.validation,
    'SYNC_TOKEN_EXPIRED': FailureKind.conflict,
    'APP_UPGRADE_REQUIRED': FailureKind.upgradeRequired,
    'RATE_LIMITED': FailureKind.rateLimited,
    'MAINTENANCE': FailureKind.network,
    'SERVICE_UNAVAILABLE': FailureKind.network,
    'INTERNAL_ERROR': FailureKind.backend,
  };

  static const _fallbackMessages = <FailureKind, String>{
    FailureKind.protocol:
        'The server returned an unexpected response. '
        'Contact your administrator.',
    FailureKind.validation: 'Check the entered values and try again.',
    FailureKind.unauthenticated:
        'Your session is no longer valid. Sign in with a new POS QR code.',
    FailureKind.expiredQr:
        'This QR code has expired. Generate a new QR code on your POS machine.',
    FailureKind.usedQr:
        'This QR code has already been used. Generate a new one on your '
        'POS machine.',
    FailureKind.forbidden: 'You do not have permission for this operation.',
    FailureKind.notFound: 'The requested record was not found.',
    FailureKind.conflict:
        'This record was changed or already exists. Refresh and try again.',
    FailureKind.upgradeRequired: 'Update the app to continue.',
    FailureKind.rateLimited: 'Too many requests. Try again shortly.',
    FailureKind.network: 'The POS server is unavailable. Try again shortly.',
    FailureKind.backend:
        'The server could not process this request. '
        'Contact your administrator.',
  };
}
