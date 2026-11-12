import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';

/// Every route that needs a signed-in session (or Demo Mode). The one list
/// both the authentication redirect and the compatibility check protect, so
/// a new signed-in screen cannot be guarded by one and missed by the other.
const signedInPaths = {
  '/home',
  '/home/scan',
  '/home/products/new',
  '/home/products/details',
  '/home/products/price',
  '/home/products/stock',
  '/home/products/edit',
  '/home/products/discounts',
  '/home/products/discounts/form',
  '/home/products/discounts/detail',
};

/// Navigation policy independent of route construction and platform services.
///
/// [demo] marks a Demo Mode sign-in (a sample QR code was chosen); it opens
/// the app without a real session.
String? authenticationRedirect(
  AsyncValue<AuthSession?> session,
  String path, {
  bool demo = false,
}) {
  const known = {
    '/',
    '/login',
    '/login/scan',
    ...signedInPaths,
    '/startup',
    '/diagnostics/initialization',
  };
  if (!known.contains(path) || path == '/diagnostics/initialization') {
    return null;
  }
  if (session.isLoading && !demo) {
    if (path == '/login' || path == '/login/scan' || path == '/startup') {
      return null;
    }
    return '/startup';
  }
  final authenticated = demo || (!session.hasError && session.value != null);
  if (authenticated &&
      const ['/login', '/login/scan', '/startup', '/'].contains(path)) {
    return '/home';
  }
  if (!authenticated &&
      (signedInPaths.contains(path) || path == '/startup' || path == '/')) {
    return '/login';
  }
  return null;
}
