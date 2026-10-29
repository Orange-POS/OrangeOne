/// Signed-in session identity.
///
/// The value stays the same while access tokens are refreshed, so routing and
/// listeners are not disturbed. [accessToken] is the token that was current
/// when the session was established or restored; request code obtains the
/// current one from the session controller (`accessToken()`).
class AuthSession {
  const new({
    required this.accessToken,
    required this.apiBase,
    required this.expiresAt,
    required this.sessionId,
    required this.userId,
    required this.posConfigId,
    required this.companyId,
    this.posSessionId,
    this.employeeId,
  });

  final String accessToken;

  /// Mobile API base URL from the POS QR, e.g. `https://pos/api/orangeone/mobile/v1`.
  final Uri apiBase;

  /// End of the sign-in (refresh token family); access tokens expire sooner
  /// and are refreshed automatically.
  final DateTime expiresAt;

  /// Server token family id; not a secret.
  final String sessionId;
  final int userId;
  final int posConfigId;
  final int companyId;
  final int? posSessionId;
  final int? employeeId;

  /// Scheme, host and port of [apiBase].
  Uri get backendOrigin => apiBase.replace(path: '');

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  @override
  String toString() => 'AuthSession(redacted)';
}
