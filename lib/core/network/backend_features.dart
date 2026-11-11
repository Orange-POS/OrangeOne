import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';

/// What the signed-in shop's backend supports: the `features` of its
/// `GET /meta` (Mobile API v2). Shops run different addon versions, so the
/// app shows a capability only when the shop advertises it; user permissions
/// still decide whether it can be used.
class BackendFeatures {
  const new(
    this.names, {
    this.apiVersion,
    this.confirmed = false,
    this.refusal,
  });

  /// The shop answered `GET /meta` with a definitive refusal (the app is too
  /// old, or the server is under maintenance). Feature names fall back to
  /// the [baseline]; the compatibility check blocks the session's screens.
  factory refused(BackendRefusal refusal) =>
      BackendFeatures(baseline.names, confirmed: true, refusal: refusal);

  /// Parses `GET /meta` `data`; anything unexpected is a protocol failure.
  factory fromMeta(Object? data) {
    if (data is! Map) throw invalidResponse;
    final features = data['features'];
    if (features is! List || features.any((name) => name is! String)) {
      throw invalidResponse;
    }
    final version = data['api_version'];
    return BackendFeatures(
      {for (final name in features) name as String},
      apiVersion: version is String ? version : null,
      confirmed: true,
    );
  }

  /// Feature names as sent by the backend (`stock_movements`, …).
  final Set<String> names;

  /// `api_version` of `GET /meta`, when known.
  final String? apiVersion;

  /// True when the list came from the shop (or Demo Mode); false for the
  /// [baseline] used while detection is pending or failed. Screens that gate
  /// a feature read the features again when they open unconfirmed.
  final bool confirmed;

  /// Why the shop refused `GET /meta`, or null when it answered normally (or
  /// could not be reached, which is never a refusal).
  final BackendRefusal? refusal;

  /// `POST /products/{id}/stock-movements` (stock Add and Remove).
  static const stockMovements = 'stock_movements';

  /// Product discounts (Mobile API 1.1, `mupi_mobile_pos_api` 19.0.2.2.0
  /// with `mupi_product_discount`). Never part of the [baseline]: a shop
  /// shows discounts only when its own `GET /meta` lists them.
  static const productDiscounts = 'product_discounts';

  /// The oldest supported addons (`mupi_mobile_pos_api` 19.0.2.0.0). Used
  /// while `GET /meta` has not answered or cannot be read, so a shop never
  /// sees a feature its backend may not have.
  static const baseline = BackendFeatures({
    'stock_adjustments',
    'categories',
    'category_create',
    'product_history',
    'product_changes',
    'product_search',
  });

  bool supports(String feature) => names.contains(feature);
}

/// Definitive `GET /meta` refusals. Transport failures and unreadable
/// replies are not refusals: they keep the unconfirmed baseline.
enum BackendRefusal {
  /// `APP_UPGRADE_REQUIRED`: the installed app is below the shop's minimum.
  appUpgradeRequired,

  /// `MAINTENANCE`: the shop's server is temporarily closed for maintenance.
  maintenance,
}

/// The features of the signed-in shop. App composition reads them from the
/// session's backend once per session; until then, and without a session,
/// it is [BackendFeatures.baseline].
final FutureProvider<BackendFeatures> backendFeaturesProvider =
    FutureProvider.autoDispose<BackendFeatures>(
      (ref) async => BackendFeatures.baseline,
      name: 'backendFeaturesProvider',
    );
