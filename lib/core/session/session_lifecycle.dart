import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app-wide sign-in state, for features that must not change while a
/// session exists (the startup configuration). App composition binds it to
/// the session controller and Demo Mode; features never see either.
abstract interface class SessionLifecycle {
  /// No session, no restore, sign-in or sign-out in progress, no Demo Mode
  /// sample session and no pending storage error.
  bool get signedOut;

  /// Signs the current session out and deletes its stored credentials.
  /// True only once the credentials are confirmed deleted; false when the
  /// secure storage could not be cleared (the login then stays blocked
  /// until it can).
  Future<bool> signOut();
}

/// Without a session controller (tests, diagnostics) nothing is signed in.
class _NoSession implements SessionLifecycle {
  const new();

  @override
  bool get signedOut => true;

  @override
  Future<bool> signOut() async => true;
}

final Provider<SessionLifecycle> sessionLifecycleProvider =
    Provider<SessionLifecycle>(
      (ref) => const _NoSession(),
      name: 'sessionLifecycleProvider',
    );
