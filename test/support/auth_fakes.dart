import 'dart:async';
import 'dart:convert';

import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/repositories/auth_repository.dart';

final testNow = DateTime.utc(2030, 1, 1, 12);
final Uri testOrigin = Uri.parse('https://pos.example');
final Uri testApiBase = Uri.parse(
  'https://pos.example/api/orangeone/mobile/v1',
);
final testSession = AuthSession(
  accessToken: 'oa_fixture_access',
  apiBase: testApiBase,
  expiresAt: testNow.add(const Duration(days: 7)),
  sessionId: 'family-1',
  userId: 2,
  posConfigId: 1,
  companyId: 1,
  posSessionId: 106,
);

/// POS login QR payload v2.
Map<String, dynamic> qrFields() => {
  'v': 2,
  'type': 'orangeone.pos-login',
  'api_base': testApiBase.toString(),
  'challenge_id': 'chl_${List.filled(32, 'a').join()}',
  'nonce': List.filled(43, 'b').join(),
  'pos_config_id': 1,
  'expires_at': testNow.add(const Duration(minutes: 2)).toIso8601String(),
};
String validQr() => jsonEncode(qrFields());

/// `Session` payload of the Mobile API.
Map<String, dynamic> sessionPayload({
  String sessionId = 'family-1',
  int companyId = 1,
  int posConfigId = 1,
}) => {
  'session_id': sessionId,
  'user': {'id': 2, 'name': 'Mobile Manager'},
  'employee': null,
  'company': {'id': companyId, 'name': 'OrangeONE'},
  'pos_config': {'id': posConfigId, 'name': 'Shop', 'pos_session_id': 106},
  'currency': {
    'code': 'CHF',
    'symbol': 'CHF',
    'decimal_places': 2,
    'position': 'before',
  },
  'permissions': {'product_read': true},
  'policy': 'independent',
  'expires_at': testNow.add(const Duration(days: 7)).toIso8601String(),
};

/// `TokenGrant` payload of the Mobile API.
Map<String, dynamic> tokenGrant({
  String access = 'oa_access_1',
  String refresh = 'or_refresh_1',
  Duration accessLifetime = const Duration(minutes: 15),
  Map<String, dynamic>? session,
}) => {
  'token_type': 'Bearer',
  'access_token': access,
  'access_expires_at': testNow.add(accessLifetime).toIso8601String(),
  'refresh_token': refresh,
  'refresh_expires_at': testNow
      .add(const Duration(hours: 12))
      .toIso8601String(),
  'session': session ?? sessionPayload(),
};

Map<String, dynamic> successEnvelope(Object? data) => {
  'data': data,
  'meta': {'request_id': 'request-1', 'api_version': '1.0.0'},
};

Map<String, dynamic> errorEnvelope(String code, {String? message}) => {
  'error': {
    'code': code,
    'message': message ?? 'Server message for $code.',
    'retryable': false,
  },
  'meta': {'request_id': 'request-1', 'api_version': '1.0.0'},
};

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};
  int writes = 0;
  int deletes = 0;
  AppFailure? failure;
  Completer<void>? pendingWrite;
  Completer<void>? pendingDelete;

  @override
  Future<String?> read(String key) async {
    if (failure != null) throw failure!;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (pendingWrite != null) await pendingWrite!.future;
    if (failure != null) throw failure!;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    if (pendingDelete != null) await pendingDelete!.future;
    if (failure != null) throw failure!;
    values.remove(key);
  }
}

class FakeAuthRepository implements AuthRepository {
  AuthSession? restored;
  Completer<AuthSession>? pendingLogin;
  AppFailure? failure;
  AppFailure? tokenFailure;
  String currentToken = testSession.accessToken;
  int signIns = 0;
  int signOuts = 0;
  int restores = 0;
  int tokenRequests = 0;
  final rejectedTokens = <String>[];

  @override
  Future<AuthSession?> restore() async {
    restores++;
    if (failure != null) throw failure!;
    return restored;
  }

  @override
  Future<AuthSession> signIn(String qrPayload) async {
    signIns++;
    if (failure != null) throw failure!;
    return pendingLogin == null ? testSession : await pendingLogin!.future;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    if (failure != null) throw failure!;
    restored = null;
  }

  @override
  Future<String> accessToken() async {
    tokenRequests++;
    if (tokenFailure != null) throw tokenFailure!;
    return currentToken;
  }

  @override
  Future<String> refreshAccessToken(String rejectedToken) async {
    rejectedTokens.add(rejectedToken);
    if (tokenFailure != null) throw tokenFailure!;
    return currentToken;
  }
}
