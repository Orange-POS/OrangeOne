import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';

/// What the signed-in shop's backend supports: the `features` of its
/// `GET /meta` (Mobile API v2). Shops run different addon versions, so the
/// app shows a capability only when the shop advertises it; user permissions
/// still decide whether it can be used.
class BackendFeatures {
  const new(this.names, {this.apiVersion});

  /// Parses `GET /meta` `data`; anything unexpected is a protocol failure.
  factory fromMeta(Object? data) {
    if (data is! Map) throw invalidResponse;
    final features = data['features'];
    if (features is! List || features.any((name) => name is! String)) {
      throw invalidResponse;
    }
    final version = data['api_version'];
    return BackendFeatures({
      for (final name in features) name as String,
    }, apiVersion: version is String ? version : null);
  }

  /// Feature names as sent by the backend (`stock_movements`, …).
  final Set<String> names;

  /// `api_version` of `GET /meta`, when known.
  final String? apiVersion;

  /// `POST /products/{id}/stock-movements` (stock Add and Remove).
  static const stockMovements = 'stock_movements';

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

/// The features of the signed-in shop. App composition reads them from the
/// session's backend once per session; until then, and without a session,
/// it is [BackendFeatures.baseline].
final FutureProvider<BackendFeatures> backendFeaturesProvider =
    FutureProvider.autoDispose<BackendFeatures>(
      (ref) async => BackendFeatures.baseline,
      name: 'backendFeaturesProvider',
    );
