import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';

/// Navigation policy independent of route construction and platform services.
String? authenticationRedirect(AsyncValue<AuthSession?> session, String path) {
  const known = {
    '/',
    '/login',
    '/login/scan',
    '/home',
    '/home/scan',
    '/home/products/new',
    '/home/products/details',
    '/home/products/price',
    '/home/products/stock',
    '/home/products/edit',
    '/startup',
    '/diagnostics/initialization',
  };
  if (!known.contains(path) || path == '/diagnostics/initialization') {
    return null;
  }
  if (session.isLoading) {
    if (path == '/login' || path == '/login/scan' || path == '/startup') {
      return null;
    }
    return '/startup';
  }
  final authenticated = !session.hasError && session.value != null;
  if (authenticated &&
      const ['/login', '/login/scan', '/startup', '/'].contains(path)) {
    return '/home';
  }
  if (!authenticated &&
      const [
        '/home',
        '/home/scan',
        '/home/products/new',
        '/home/products/details',
        '/home/products/price',
        '/home/products/stock',
        '/home/products/edit',
        '/startup',
        '/',
      ].contains(path)) {
    return '/login';
  }
  return null;
}
