import 'dart:async';

import 'package:dio/dio.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/data/data_sources/auth_remote_data_source.dart';
import 'package:orange_one/features/authentication/data/models/login_qr_model.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/repositories/auth_repository.dart';

class OdooAuthRepository implements AuthRepository {
  new(this._remote, this._store, this._configuration, this._now);
  final AuthRemoteDataSource _remote;
  final SecretStore _store;
  final ApiConfiguration _configuration;
  final DateTime Function() _now;
  var _epoch = 0;
  CancelToken? _pending;
  Future<void> _storageWork = Future<void>.value();
  Future<void>? _cleanup;

  static const _cleanupLimit = Duration(seconds: 2);

  Future<void> _waitForCleanup() =>
      _cleanup!.timeout(_cleanupLimit, onTimeout: () => throw storageFailure);

  String get _key => 'orangeone.${_configuration.environment.name}.session.v1';

  Future<void> _storeInOrder(Future<void> Function() operation) {
    final next = _storageWork.then((_) => operation());
    // Keep the queue usable after a failure; return the error to its caller.
    _storageWork = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  @override
  Future<AuthSession> signIn(String qrPayload) async {
    if (_cleanup != null) throw storageFailure;
    if (_pending != null) throw cancelledOperation;
    final challenge = LoginQrModel.parse(qrPayload, _configuration, _now());
    final generation = _epoch;
    final cancel = CancelToken();
    _pending = cancel;
    try {
      final session = await _remote.validate(challenge, cancel);
      if (session.isExpired(_now())) throw invalidSession;
      await _storeInOrder(() async {
        if (generation != _epoch) throw cancelledOperation;
        await _store.write(_key, SessionModel.encode(session));
      });
      if (generation != _epoch) throw cancelledOperation;
      return session;
    } finally {
      if (identical(_pending, cancel)) _pending = null;
    }
  }

  @override
  Future<AuthSession?> restore() {
    final generation = _epoch;
    return _restore().timeout(
      const Duration(seconds: 15),
      onTimeout: () async {
        if (generation == _epoch || _cleanup != null) await signOut();
        return null;
      },
    );
  }

  Future<AuthSession?> _restore() async {
    if (_cleanup != null) {
      await _waitForCleanup();
      return null;
    }
    final generation = _epoch;
    final saved = await _store.read(_key);
    if (generation != _epoch) return null;
    if (saved == null) return null;
    AuthSession stored;
    try {
      stored = SessionModel.decode(saved, _configuration);
    } on FormatException {
      await signOut();
      return null;
    } on AppFailure {
      await signOut();
      return null;
    }
    if (stored.isExpired(_now())) {
      await signOut();
      return null;
    }
    final cancel = CancelToken();
    _pending = cancel;
    try {
      final verified = await _remote.check(stored, cancel);
      if (verified.isExpired(_now())) throw invalidSession;
      if (generation != _epoch) return null;
      return verified;
    } on AppFailure {
      if (generation != _epoch) return null;
      // A saved session is usable only after this one successful check.
      await signOut();
      return null;
    } finally {
      if (identical(_pending, cancel)) _pending = null;
    }
  }

  @override
  Future<void> signOut() {
    if (_cleanup != null) return _waitForCleanup();
    _epoch++;
    _pending?.cancel();
    _pending = null;
    // Platform storage cannot be cancelled. Keep its real completion in the
    // ordered queue, even after the caller's bounded wait reports an error.
    final cleanup = _storeInOrder(() => _store.delete(_key));
    _cleanup = cleanup;
    unawaited(
      cleanup.then<void>(
        (_) => _cleanup = null,
        onError: (Object error, StackTrace stack) => _cleanup = null,
      ),
    );
    return _waitForCleanup();
  }

  void dispose() => _pending?.cancel();
}
