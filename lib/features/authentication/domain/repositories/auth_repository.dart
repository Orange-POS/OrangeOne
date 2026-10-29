import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';

abstract interface class AuthRepository {
  Future<AuthSession?> restore();
  Future<AuthSession> signIn(String qrPayload);
  Future<void> signOut();

  /// A valid access token for the signed-in session, refreshed shortly before
  /// it expires. Concurrent callers share one refresh request.
  Future<String> accessToken();

  /// Refreshes after the server rejected [rejectedToken] as expired. Returns
  /// the current token without a request when another caller already did.
  Future<String> refreshAccessToken(String rejectedToken);
}
