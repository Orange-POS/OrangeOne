import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';

/// Supplies the signed-in session's access tokens (implemented by app
/// composition on top of authentication).
abstract interface class AccessTokenSource {
  /// A currently valid token, refreshed shortly before it expires.
  Future<String> accessToken();

  /// A new token after the server rejected [rejectedToken] as expired.
  /// Concurrent callers share one refresh.
  Future<String> refreshAccessToken(String rejectedToken);
}

/// App composition binds this to the signed-in session; it throws while
/// signed out.
final authenticatedMobileApiProvider = Provider<AuthenticatedMobileApi>(
  (ref) => throw invalidSession,
  name: 'authenticatedMobileApiProvider',
);

/// [MobileApiClient] bound to one signed-in session.
///
/// Each request carries the current access token. When the server answers
/// `TOKEN_EXPIRED`, the token is refreshed once and the request repeated;
/// this is safe for writes because the server rejects the token before the
/// handler runs, and writes carry an `Idempotency-Key`.
class AuthenticatedMobileApi {
  new(this._client, {required this.apiBase, required this._tokens});

  final MobileApiClient _client;
  final AccessTokenSource _tokens;

  /// Mobile API base of the session's POS server.
  final Uri apiBase;

  Future<MobileApiResponse> send(
    MobileApiMethod method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? language,
    String? idempotencyKey,
    String? ifMatchVersion,
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) async {
    Future<MobileApiResponse> attempt(String token) => _client.send(
      method,
      path,
      apiBase: apiBase,
      body: body,
      query: query,
      accessToken: token,
      language: language,
      idempotencyKey: idempotencyKey,
      ifMatchVersion: ifMatchVersion,
      ifNoneMatch: ifNoneMatch,
      cancelToken: cancelToken,
    );

    final token = await _tokens.accessToken();
    try {
      return await attempt(token);
    } on AppFailure catch (failure) {
      if (failure.code != 'TOKEN_EXPIRED') rethrow;
      return await attempt(await _tokens.refreshAccessToken(token));
    }
  }
}
