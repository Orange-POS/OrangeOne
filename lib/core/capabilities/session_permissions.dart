import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Effective permissions of the signed-in user (`Session.permissions` of the
/// token grant and `GET /auth/session`). Kept in memory only: never stored
/// with the session record or in the read cache.
///
/// [unknown] (no session, Demo Mode, or a reply without permissions) never
/// restricts: the server still enforces every permission (403), and product
/// screens keep using the per-product `Product.permissions`.
class SessionPermissions {
  const new(this._granted);

  static const unknown = SessionPermissions({});

  final Map<String, bool> _granted;

  bool get known => _granted.isNotEmpty;

  /// False only when the session reported [key] and it is not granted. A key
  /// the backend does not know (an older addon) is treated as not granted.
  bool allows(String key) => !known || (_granted[key] ?? false);
}

/// The signed-in user's permissions; app composition binds it to the
/// session. [SessionPermissions.unknown] without a session.
final Provider<SessionPermissions> sessionPermissionsProvider =
    Provider<SessionPermissions>(
      (ref) => SessionPermissions.unknown,
      name: 'sessionPermissionsProvider',
    );
