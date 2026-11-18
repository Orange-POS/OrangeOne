import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';

/// Route of the compatibility screen (update required, maintenance, server
/// not supported).
const compatibilityPath = '/compatibility';

/// Entry route of each sign-in method: the starting component shown without
/// a session. The resolver only opens available methods
/// ([StartupConfiguration.effectiveMethod]); the others have no contract
/// and fall back to QR login.
String startupEntryPath(AuthenticationMethod method) => switch (method) {
  AuthenticationMethod.qrLogin => '/login',
  // No confirmed backend contracts yet: never opened.
  AuthenticationMethod.oidc || AuthenticationMethod.credentials => '/login',
};

/// Bootstrap Resolver: the route for [path] given the session, Demo Mode,
/// the saved startup configuration and the shop's compatibility.
///
/// Order:
/// 1. Compatibility. A real, signed-in session whose shop refused this app
///    (update required, maintenance, server too old) sees only the
///    compatibility screen; Demo Mode is never blocked.
/// 2. Authentication, unchanged ([authenticationRedirect]).
/// 3. The starting component. Without a session, the login entry is the
///    startup configuration's workflow entry (read during bootstrap, before
///    the first frame, so routing never waits for storage).
String? bootstrapRedirect({
  required AsyncValue<AuthSession?> session,
  required String path,
  required StartupConfiguration startup,
  required CompatibilityStatus compatibility,
  bool demo = false,
}) {
  final signedIn =
      !demo && !session.isLoading && !session.hasError && session.value != null;
  final blocked = signedIn && compatibility.blocked;
  if (path == compatibilityPath) {
    if (blocked) return null;
    return demo || signedIn ? '/home' : '/login';
  }
  if (blocked && signedInPaths.contains(path)) return compatibilityPath;

  final target = authenticationRedirect(session, path, demo: demo);
  if (target != '/login' && !(target == null && path == '/login')) {
    return target;
  }
  // The login entry: the selected workflow's starting component.
  final entry = startupEntryPath(startup.effectiveMethod);
  return entry == path ? null : entry;
}
