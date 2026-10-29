import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_version.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/data/data_sources/auth_remote_data_source.dart';
import 'package:orange_one/features/authentication/data/repositories/odoo_auth_repository.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/domain/repositories/auth_repository.dart';
import 'package:orange_one/features/authentication/domain/use_cases/authenticate_with_qr.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = OdooAuthRepository(
    AuthRemoteDataSource(ref.watch(mobileApiClientProvider)),
    ref.watch(secretStoreProvider),
    ref.watch(apiConfigurationProvider),
    ref.watch(utcNowProvider),
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    // The same version the client sends as X-App-Version.
    appVersion: ref.watch(appVersionProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
}, name: 'authRepositoryProvider');

final authenticateWithQrProvider = Provider<AuthenticateWithQr>(
  (ref) => AuthenticateWithQr(ref.watch(authRepositoryProvider)),
  name: 'authenticateWithQrProvider',
);

// Session state must survive navigation between the login and protected routes.
final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, AuthSession?>(
      SessionController.new,
      retry: (count, error) => null,
      name: 'sessionControllerProvider',
    );

class SessionController extends AsyncNotifier<AuthSession?> {
  Timer? _expiry;
  var _generation = 0;
  var _busy = false;
  var _signingOut = false;

  @override
  Future<AuthSession?> build() async {
    final generation = ++_generation;
    ref.onDispose(() => _expiry?.cancel());
    final session = await ref.watch(authRepositoryProvider).restore();
    if (!ref.mounted || generation != _generation) return null;
    _scheduleExpiry(session);
    return session;
  }

  void _scheduleExpiry(AuthSession? session) {
    _expiry?.cancel();
    if (session == null) return;
    final remaining = session.expiresAt.difference(ref.read(utcNowProvider)());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      unawaited(signOut());
    });
  }

  Future<bool> signIn(String rawQr) async {
    if (_busy || state.isLoading || state.value != null) return false;
    _busy = true;
    final generation = ++_generation;
    state = const AsyncLoading();
    try {
      final session = await ref.read(authenticateWithQrProvider)(rawQr);
      if (!ref.mounted || generation != _generation) return false;
      _scheduleExpiry(session);
      state = AsyncData(session);
      return true;
    } on FormatException catch (_, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(invalidQr, stack);
      }
      return false;
    } on AppFailure catch (error, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(error, stack);
      }
      return false;
    } on Exception catch (_, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(
          const AppFailure(
            FailureKind.backend,
            'Sign-in could not be completed. Generate a new POS QR code '
            'and try again.',
          ),
          stack,
        );
      }
      return false;
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  /// A valid access token for the current session. Refreshes it when it is
  /// about to expire; concurrent callers share one refresh. The session state
  /// does not change on refresh. A rejected refresh signs out.
  Future<String> accessToken() =>
      _token((repository) => repository.accessToken());

  /// Refreshes after the server reported [rejectedToken] as expired.
  Future<String> refreshAccessToken(String rejectedToken) =>
      _token((repository) => repository.refreshAccessToken(rejectedToken));

  Future<String> _token(
    Future<String> Function(AuthRepository repository) operation,
  ) async {
    if (state.value == null) throw invalidSession;
    try {
      return await operation(ref.read(authRepositoryProvider));
    } on AppFailure catch (failure) {
      if (failure.kind == FailureKind.unauthenticated) await signOut();
      rethrow;
    }
  }

  void clearLoginFailure() {
    if (!_busy && state.hasError) state = const AsyncData(null);
  }

  Future<void> revalidate() async {
    if (_busy || state.isLoading || state.value == null) return;
    await retryRestore();
  }

  Future<void> retryRestore() async {
    if (_busy || state.isLoading) return;
    _busy = true;
    final generation = ++_generation;
    _expiry?.cancel();
    state = const AsyncLoading();
    try {
      final session = await ref.read(authRepositoryProvider).restore();
      if (!ref.mounted || generation != _generation) return;
      _scheduleExpiry(session);
      state = AsyncData(session);
    } on AppFailure catch (error, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(error, stack);
      }
    } on Exception catch (_, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(storageFailure, stack);
      }
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    final generation = ++_generation;
    _busy = true;
    _expiry?.cancel();
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (ref.mounted && generation == _generation) {
        state = const AsyncData(null);
      }
    } on AppFailure catch (error, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(error, stack);
      }
    } on Exception catch (_, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(storageFailure, stack);
      }
    } finally {
      _signingOut = false;
      if (generation == _generation) _busy = false;
    }
  }
}
