import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/features/authentication/data/models/device_model.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/entities/login_challenge.dart';

const qrExchangePath = '/auth/qr-exchange';
const tokenRefreshPath = '/auth/token/refresh';
const sessionPath = '/auth/session';
const logoutPath = '/auth/logout';

/// Mobile API v2 authentication endpoints. Failures arrive as typed
/// [AppFailure]s from [MobileApiClient] (error codes, never server text
/// matching).
class AuthRemoteDataSource {
  const new(this._client);
  final MobileApiClient _client;

  Future<SessionCredentials> exchange(
    LoginChallenge challenge,
    DeviceModel device,
    CancelToken cancelToken,
  ) async {
    final response = await _client.send(
      MobileApiMethod.post,
      qrExchangePath,
      apiBase: challenge.apiBase,
      body: {
        'challenge_id': challenge.challengeId,
        'nonce': challenge.nonce,
        'pos_config_id': challenge.posConfigId,
        'device': device.toJson(),
      },
      cancelToken: cancelToken,
    );
    final credentials = SessionModel.fromGrant(
      response.data,
      challenge.apiBase,
    );
    if (credentials.session.posConfigId != challenge.posConfigId) {
      throw invalidResponse;
    }
    return credentials;
  }

  /// Rotates the refresh token. The previous refresh token becomes invalid.
  Future<SessionCredentials> refresh(
    SessionCredentials current,
    String installId,
    CancelToken cancelToken,
  ) async {
    final apiBase = current.session.apiBase;
    final response = await _client.send(
      MobileApiMethod.post,
      tokenRefreshPath,
      apiBase: apiBase,
      body: {'refresh_token': current.refreshToken, 'install_id': installId},
      cancelToken: cancelToken,
    );
    final rotated = SessionModel.fromGrant(response.data, apiBase);
    if (!SessionModel.sameIdentity(current.session, rotated.session)) {
      throw invalidSession;
    }
    return rotated;
  }

  /// Validates [current] and returns the server's view of the session.
  Future<AuthSession> session(
    SessionCredentials current,
    CancelToken cancelToken,
  ) async {
    final response = await _client.send(
      MobileApiMethod.get,
      sessionPath,
      apiBase: current.session.apiBase,
      accessToken: current.accessToken,
      cancelToken: cancelToken,
    );
    final verified = SessionModel.fromSession(
      response.data,
      current.session.apiBase,
      current.accessToken,
    );
    if (!SessionModel.sameIdentity(current.session, verified)) {
      throw invalidSession;
    }
    return verified;
  }

  /// Revokes the token family on the server; accepted in any token state.
  Future<void> logout(Uri apiBase, String accessToken) async {
    await _client.send(
      MobileApiMethod.post,
      logoutPath,
      apiBase: apiBase,
      accessToken: accessToken,
    );
  }
}
