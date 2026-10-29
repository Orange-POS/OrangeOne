import 'dart:async';

import 'package:dio/dio.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/data/data_sources/auth_remote_data_source.dart';
import 'package:orange_one/features/authentication/data/models/device_model.dart';
import 'package:orange_one/features/authentication/data/models/login_qr_model.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/repositories/auth_repository.dart';

class OdooAuthRepository implements AuthRepository {
  new(
    this._remote,
    this._store,
    this._configuration,
    this._now, {
    required this._platform,
    required this._appVersion,
  });
  final AuthRemoteDataSource _remote;
  final SecretStore _store;
  final ApiConfiguration _configuration;
  final DateTime Function() _now;
  final String _platform;
  final String _appVersion;
  var _epoch = 0;
  CancelToken? _pending;
  CancelToken? _refreshCancel;
  Future<void> _storageWork = Future<void>.value();
  Future<void>? _cleanup;
  SessionCredentials? _credentials;
  Future<String>? _refreshing;
  Future<String>? _installIdLoad;

  static const _cleanupLimit = Duration(seconds: 2);
  static const _restoreLimit = Duration(seconds: 15);

  /// Refresh shortly before expiry so requests do not race the deadline.
  static const _refreshMargin = Duration(seconds: 30);

  Future<void> _waitForCleanup() =>
      _cleanup!.timeout(_cleanupLimit, onTimeout: () => throw storageFailure);

  String get _environment => _configuration.environment.name;
  String get _key => 'orangeone.$_environment.session.v2';

  /// Version 1 (JWT) sessions cannot be used with the v2 API.
  String get _legacyKey => 'orangeone.$_environment.session.v1';

  /// Survives logout: the server binds token families to this installation.
  String get _installKey => 'orangeone.$_environment.install_id';

  Future<void> _storeInOrder(Future<void> Function() operation) {
    final next = _storageWork.then((_) => operation());
    // Keep the queue usable after a failure; return the error to its caller.
    _storageWork = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  Future<void> _persist(SessionCredentials credentials, int generation) =>
      _storeInOrder(() async {
        if (generation != _epoch) throw cancelledOperation;
        await _store.write(_key, SessionModel.encode(credentials));
      });

  bool _usable(SessionCredentials credentials) =>
      credentials.accessExpiresAt.isAfter(_now().add(_refreshMargin));

  bool _renewable(SessionCredentials credentials) {
    final now = _now();
    return !credentials.session.isExpired(now) &&
        credentials.refreshExpiresAt.isAfter(now);
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
      final device = DeviceModel(
        installId: await _installId(),
        platform: _platform,
        appVersion: _appVersion,
      );
      final credentials = await _remote.exchange(challenge, device, cancel);
      if (!_renewable(credentials)) throw invalidSession;
      await _persist(credentials, generation);
      if (generation != _epoch) throw cancelledOperation;
      _credentials = credentials;
      return credentials.session;
    } finally {
      if (identical(_pending, cancel)) _pending = null;
    }
  }

  @override
  Future<AuthSession?> restore() {
    final generation = _epoch;
    return _restore().timeout(
      _restoreLimit,
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
    final legacy = await _store.read(_legacyKey);
    if (generation != _epoch) return null;
    if (legacy != null) await _storeInOrder(() => _store.delete(_legacyKey));
    if (saved == null) return null;
    SessionCredentials stored;
    try {
      stored = SessionModel.decode(saved, _configuration);
    } on FormatException {
      await signOut();
      return null;
    } on AppFailure {
      await signOut();
      return null;
    }
    if (!_renewable(stored)) {
      await signOut();
      return null;
    }
    final cancel = CancelToken();
    _pending = cancel;
    try {
      var current = stored;
      if (!_usable(current)) {
        current = await _rotate(current, cancel, generation);
      }
      AuthSession verified;
      try {
        verified = await _remote.session(current, cancel);
      } on AppFailure catch (failure) {
        // Device clock ahead of the server: refresh once and validate again.
        if (failure.code != 'TOKEN_EXPIRED') rethrow;
        current = await _rotate(current, cancel, generation);
        verified = await _remote.session(current, cancel);
      }
      if (generation != _epoch) return null;
      if (verified.isExpired(_now())) throw invalidSession;
      // A saved session is usable only after this one successful check.
      _credentials = current.withSession(verified);
      return verified;
    } on AppFailure {
      if (generation != _epoch) return null;
      await signOut();
      return null;
    } finally {
      if (identical(_pending, cancel)) _pending = null;
    }
  }

  Future<SessionCredentials> _rotate(
    SessionCredentials current,
    CancelToken cancel,
    int generation,
  ) async {
    final rotated = await _remote.refresh(current, await _installId(), cancel);
    if (generation != _epoch) throw cancelledOperation;
    await _persist(rotated, generation);
    return rotated;
  }

  @override
  Future<String> accessToken() async {
    final current = _credentials;
    if (current == null) throw invalidSession;
    if (_usable(current)) return current.accessToken;
    return await _refresh();
  }

  @override
  Future<String> refreshAccessToken(String rejectedToken) async {
    final current = _credentials;
    if (current == null) throw invalidSession;
    if (current.accessToken != rejectedToken) return current.accessToken;
    return await _refresh();
  }

  /// One refresh at a time: reusing a rotated refresh token would make the
  /// server revoke the whole session.
  Future<String> _refresh() =>
      _refreshing ??= _refreshCurrent().whenComplete(() => _refreshing = null);

  Future<String> _refreshCurrent() async {
    final current = _credentials;
    if (current == null || !_renewable(current)) throw invalidSession;
    final generation = _epoch;
    final cancel = CancelToken();
    _refreshCancel = cancel;
    try {
      final rotated = await _remote.refresh(
        current,
        await _installId(),
        cancel,
      );
      if (generation != _epoch) throw cancelledOperation;
      _credentials = rotated;
      try {
        await _persist(rotated, generation);
      } on AppFailure catch (failure) {
        // The rotated pair stays usable in memory; a later restart without it
        // needs a new QR login.
        if (failure.kind != FailureKind.storage) rethrow;
      }
      return rotated.accessToken;
    } on AppFailure catch (failure) {
      if (failure.code == 'DEVICE_MISMATCH') throw invalidSession;
      rethrow;
    } finally {
      if (identical(_refreshCancel, cancel)) _refreshCancel = null;
    }
  }

  Future<String> _installId() async {
    final load = _installIdLoad ??= _loadInstallId();
    try {
      return await load;
    } on AppFailure {
      if (identical(_installIdLoad, load)) _installIdLoad = null;
      rethrow;
    }
  }

  Future<String> _loadInstallId() async {
    final saved = await _store.read(_installKey);
    if (saved != null && DeviceModel.isInstallId(saved)) return saved;
    final created = DeviceModel.newInstallId();
    await _store.write(_installKey, created);
    return created;
  }

  @override
  Future<void> signOut() {
    if (_cleanup != null) return _waitForCleanup();
    final revoked = _credentials;
    _credentials = null;
    _epoch++;
    _pending?.cancel();
    _pending = null;
    _refreshCancel?.cancel();
    _refreshCancel = null;
    if (revoked != null) {
      // Best effort: local cleanup never waits for the network.
      unawaited(
        _remote
            .logout(revoked.session.apiBase, revoked.accessToken)
            .then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
      );
    }
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

  void dispose() {
    _pending?.cancel();
    _refreshCancel?.cancel();
  }
}
