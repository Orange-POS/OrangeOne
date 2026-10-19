import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/features/authentication/data/models/login_qr_model.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/entities/login_challenge.dart';

class AuthRemoteDataSource {
  const new(this._client);
  final JsonRpcClient _client;

  Future<AuthSession> validate(
    LoginChallenge challenge,
    CancelToken cancelToken,
  ) async {
    final result = await _client.call(
      validateChallengePath,
      backendOrigin: challenge.backendOrigin,
      params: {
        'challenge': challenge.challenge,
        'nonce': challenge.nonce,
        'pos_session_id': challenge.posSessionId,
        'pos_config_id': challenge.posConfigId,
        'device_name': 'OrangeONE mobile',
      },
      cancelToken: cancelToken,
    );
    _checkResult(result);
    final session = SessionModel.fromResult(result, challenge.backendOrigin);
    if (session.posSessionId != challenge.posSessionId ||
        session.posConfigId != challenge.posConfigId) {
      throw invalidResponse;
    }
    return session;
  }

  Future<AuthSession> check(AuthSession stored, CancelToken cancelToken) async {
    final result = await _client.call(
      checkTokenPath,
      backendOrigin: stored.backendOrigin,
      accessToken: stored.accessToken,
      cancelToken: cancelToken,
    );
    _checkResult(result, tokenCheck: true);
    final verified = SessionModel.fromResult(
      result,
      stored.backendOrigin,
      existingToken: stored.accessToken,
      employeeId: stored.employeeId,
    );
    if (verified.tokenId != stored.tokenId ||
        verified.userId != stored.userId ||
        verified.posSessionId != stored.posSessionId ||
        verified.posConfigId != stored.posConfigId ||
        verified.companyId != stored.companyId) {
      throw invalidSession;
    }
    return verified;
  }

  void _checkResult(Map<String, dynamic> result, {bool tokenCheck = false}) {
    if (result['ok'] == true) return;
    if (result['ok'] != false || result['error'] is! String) {
      throw invalidResponse;
    }
    if (tokenCheck) throw invalidSession;
    final error = result['error'];
    if (error == 'This QR code has expired.') {
      throw const AppFailure(
        FailureKind.expiredQr,
        'This QR code has expired. Generate a new QR code '
        'on your POS machine.',
      );
    }
    if (error == 'This QR code has already been used.') {
      throw const AppFailure(
        FailureKind.usedQr,
        'This QR code has already been used. Generate a new one '
        'on your POS machine.',
      );
    }
    if (error == 'POS session is no longer opened.' ||
        error == 'This QR code has been revoked.') {
      throw const AppFailure(
        FailureKind.unauthenticated,
        'This POS login is no longer available. Ask your administrator '
        'for a new QR code.',
      );
    }
    if (const [
      'Invalid QR code.',
      'Missing challenge.',
      'Missing nonce.',
      'Invalid QR code verification data.',
      'QR code does not match POS session.',
      'QR code does not match POS config.',
      'Invalid POS session.',
      'Invalid POS config.',
      'Invalid QR code state.',
    ].contains(error)) {
      throw invalidQr;
    }
    throw const AppFailure(
      FailureKind.backend,
      'The server could not complete sign-in. Ask your administrator for help.',
    );
  }
}
