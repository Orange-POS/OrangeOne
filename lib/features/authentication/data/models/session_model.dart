import 'dart:convert';

import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/formatting/utc_timestamp.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';

/// A session plus the secrets that keep it alive. Data layer only: the
/// refresh token never reaches presentation state. Never logged.
class SessionCredentials {
  const new({
    required this.session,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final AuthSession session;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  String get accessToken => session.accessToken;

  /// The same identity with a newer access token.
  SessionCredentials withSession(AuthSession value) => SessionCredentials(
    session: value,
    refreshToken: refreshToken,
    accessExpiresAt: accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt,
  );

  @override
  String toString() => 'SessionCredentials(redacted)';
}

/// Maps `TokenGrant` / `Session` payloads and the secure-storage record.
abstract final class SessionModel {
  static const _format = 2;

  /// Parses a `TokenGrant` (`/auth/qr-exchange`, `/auth/token/refresh`).
  static SessionCredentials fromGrant(Object? data, Uri apiBase) {
    if (data is! Map<String, dynamic> || data['token_type'] != 'Bearer') {
      throw invalidResponse;
    }
    final accessToken = _token(data['access_token']);
    return SessionCredentials(
      session: fromSession(data['session'], apiBase, accessToken),
      refreshToken: _token(data['refresh_token']),
      accessExpiresAt: _time(data['access_expires_at']),
      refreshExpiresAt: _time(data['refresh_expires_at']),
    );
  }

  /// Parses a `Session` (`/auth/session` or `TokenGrant.session`).
  static AuthSession fromSession(
    Object? data,
    Uri apiBase,
    String accessToken,
  ) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final sessionId = data['session_id'];
    final posConfig = data['pos_config'];
    final employee = data['employee'];
    if (sessionId is! String ||
        sessionId.isEmpty ||
        sessionId.length > 128 ||
        posConfig is! Map<String, dynamic> ||
        (employee != null && employee is! Map<String, dynamic>)) {
      throw invalidResponse;
    }
    final posSession = posConfig['pos_session_id'];
    if (posSession != null && (posSession is! int || posSession <= 0)) {
      throw invalidResponse;
    }
    return AuthSession(
      accessToken: accessToken,
      apiBase: apiBase,
      expiresAt: _time(data['expires_at']),
      sessionId: sessionId,
      userId: _nestedId(data['user']),
      companyId: _nestedId(data['company']),
      posConfigId: _id(posConfig['id']),
      posSessionId: posSession as int?,
      employeeId: employee == null ? null : _nestedId(employee),
    );
  }

  /// True when [other] belongs to the same sign-in as [session].
  static bool sameIdentity(AuthSession session, AuthSession other) =>
      session.sessionId == other.sessionId &&
      session.userId == other.userId &&
      session.companyId == other.companyId &&
      session.posConfigId == other.posConfigId &&
      session.apiBase == other.apiBase;

  static String encode(SessionCredentials credentials) {
    final session = credentials.session;
    return jsonEncode({
      'format': _format,
      'api_base': session.apiBase.toString(),
      'access_token': session.accessToken,
      'refresh_token': credentials.refreshToken,
      'access_expires_at': credentials.accessExpiresAt.toIso8601String(),
      'refresh_expires_at': credentials.refreshExpiresAt.toIso8601String(),
      'expires_at': session.expiresAt.toIso8601String(),
      'session_id': session.sessionId,
      'user_id': session.userId,
      'company_id': session.companyId,
      'pos_config_id': session.posConfigId,
      'pos_session_id': session.posSessionId,
      'employee_id': session.employeeId,
    });
  }

  static SessionCredentials decode(
    String value,
    ApiConfiguration configuration,
  ) {
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic> ||
        json['format'] != _format ||
        json['api_base'] is! String) {
      throw invalidResponse;
    }
    final sessionId = json['session_id'];
    if (sessionId is! String || sessionId.isEmpty) throw invalidResponse;
    return SessionCredentials(
      session: AuthSession(
        accessToken: _token(json['access_token']),
        apiBase: configuration.validateApiBase(json['api_base'] as String),
        expiresAt: _time(json['expires_at']),
        sessionId: sessionId,
        userId: _id(json['user_id']),
        companyId: _id(json['company_id']),
        posConfigId: _id(json['pos_config_id']),
        posSessionId: _optionalId(json['pos_session_id']),
        employeeId: _optionalId(json['employee_id']),
      ),
      refreshToken: _token(json['refresh_token']),
      accessExpiresAt: _time(json['access_expires_at']),
      refreshExpiresAt: _time(json['refresh_expires_at']),
    );
  }

  static String _token(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 8192 ||
        RegExp(r'\s').hasMatch(value)) {
      throw invalidResponse;
    }
    return value;
  }

  static DateTime _time(Object? value) {
    if (value is! String) throw invalidResponse;
    try {
      return parseUtcTimestamp(value);
    } on FormatException {
      throw invalidResponse;
    }
  }

  static int _id(Object? value) {
    if (value is! int || value <= 0) throw invalidResponse;
    return value;
  }

  static int? _optionalId(Object? value) => value == null ? null : _id(value);

  static int _nestedId(Object? value) {
    if (value is! Map<String, dynamic>) throw invalidResponse;
    return _id(value['id']);
  }
}
