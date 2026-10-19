import 'dart:async';
import 'dart:convert';

import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/repositories/auth_repository.dart';

final testNow = DateTime.utc(2030, 1, 1, 12);
final Uri testOrigin = Uri.parse('https://pos.example');
final testSession = AuthSession(
  accessToken: 'fixture.token.signature',
  backendOrigin: testOrigin,
  expiresAt: testNow.add(const Duration(hours: 8)),
  tokenId: 7,
  userId: 2,
  posSessionId: 106,
  posConfigId: 1,
  companyId: 1,
);

Map<String, dynamic> qrFields() => {
  'challenge': List.filled(43, 'a').join(),
  'nonce': List.filled(43, 'b').join(),
  'pos_session_id': 106,
  'pos_config_id': 1,
  'backend_url': testOrigin.toString(),
  'rest_endpoint_url': '$testOrigin/mupi/mobile/auth/challenge/validate',
  'expires_at': testNow.add(const Duration(minutes: 5)).toIso8601String(),
};
String validQr() => jsonEncode(qrFields());
Map<String, dynamic> tokenResult() => {
  'ok': true,
  'access_token': testSession.accessToken,
  'token_type': 'Bearer',
  'expires_at': '2030-01-01 20:00:00',
  'token_id': 7,
  'user_id': 2,
  'pos_session_id': 106,
  'pos_config_id': 1,
  'company_id': 1,
  'employee_id': false,
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
  int signIns = 0;
  int signOuts = 0;
  int restores = 0;

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
}
