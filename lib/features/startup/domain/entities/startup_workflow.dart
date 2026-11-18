/// How the app signs a user in. Each method is a separate authentication
/// contract with the shop's backend; one is never a stand-in for another.
///
/// A method is [available] only when this build implements a confirmed
/// backend contract for it:
/// - [qrLogin]: the POS QR challenge and `POST /auth/qr-exchange` of the
///   Mobile API v1 (confirmed; every supported addon implements it).
/// - [oidc]: OpenID Connect through a customer identity provider. No
///   OrangeONE backend contract exists yet (discovery document, client
///   registration, token exchange for a Mobile API token), so it cannot be
///   selected; see `docs/bootstrap-and-capabilities.md`.
/// - [credentials]: username and password. Not OIDC; the Mobile API has no
///   credentials endpoint, so it cannot be selected either.
enum AuthenticationMethod {
  qrLogin(storageValue: 'qr_login', available: true),
  oidc(storageValue: 'oidc', available: false),
  credentials(storageValue: 'credentials_login', available: false);

  new({required this.storageValue, required this.available});

  /// Stable value kept in the device's saved configuration.
  final String storageValue;
  final bool available;

  /// The method saved as [value], or null when unknown.
  static AuthenticationMethod? fromStorage(String? value) {
    for (final method in values) {
      if (method.storageValue == value) return method;
    }
    return null;
  }
}

/// The device's saved startup configuration: only the sign-in method chosen
/// before any shop is known.
///
/// Everything that depends on the customer is discovered per session and
/// never saved here: the backend identity comes from the signed-in session
/// (QR `api_base`, company, user), the API compatibility profile and the
/// supported workflows from that shop's `GET /meta`. So a saved profile can
/// never outlive the shop it belonged to.
class StartupConfiguration {
  const new({this.method = AuthenticationMethod.qrLogin});

  /// Current layout of the saved configuration; older layouts are migrated
  /// when read.
  static const schemaVersion = 2;

  /// Used when nothing is saved, the saved value is unknown or no longer
  /// available, or the storage cannot be read.
  static const fallback = StartupConfiguration();

  final AuthenticationMethod method;

  /// [method] when it can run in this build, else QR login: a customer
  /// without a verified alternative always keeps QR login.
  AuthenticationMethod get effectiveMethod =>
      method.available ? method : fallback.method;
}
