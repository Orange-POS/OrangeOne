import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:orange_one/core/capabilities/session_permissions.dart';
import 'package:orange_one/core/network/backend_features.dart';

/// App features gated by the shop's backend and the user's permissions.
///
/// [requiredFeatures] must all be listed by `GET /meta`; [optionalFeatures]
/// select workflow variants; [permissions] must all be granted.
enum AppFeature {
  productLookup(permissions: {'product_read'}),
  productCreate(permissions: {'product_create', 'product_update_price'}),
  productEdit(permissions: {'product_update_name'}),
  priceUpdate(permissions: {'product_update_price'}),
  stockUpdate(
    requiredFeatures: {'stock_adjustments'},
    optionalFeatures: {BackendFeatures.stockMovements},
    permissions: {'stock_adjust'},
  ),
  productHistory(
    requiredFeatures: {'product_history'},
    permissions: {'product_history_read'},
  ),

  /// Discount Overview and Details (read-only without [discountManage]).
  discounts(
    requiredFeatures: {BackendFeatures.productDiscounts},
    permissions: {'discount_read'},
  ),

  /// Create, edit, pause, resume and archive discounts. Per product the
  /// backend also reports `discount_manage` (discountable products only).
  discountManage(
    requiredFeatures: {BackendFeatures.productDiscounts},
    permissions: {'discount_read', 'discount_manage'},
  );

  new({
    this.requiredFeatures = const {},
    this.optionalFeatures = const {},
    this.permissions = const {},
  });

  final Set<String> requiredFeatures;
  final Set<String> optionalFeatures;
  final Set<String> permissions;
}

enum FeatureStatus {
  available,

  /// Supported by the shop, but the user lacks a permission.
  disabled,

  /// Not supported by the shop's backend: not shown at all.
  hidden,
}

/// One feature's availability and the optional backend features (workflow
/// variants) the shop supports for it.
class FeatureAvailability {
  const new(this.feature, this.status, {this.extensions = const {}});

  final AppFeature feature;
  final FeatureStatus status;

  /// The [AppFeature.optionalFeatures] the shop lists.
  final Set<String> extensions;

  bool get visible => status != FeatureStatus.hidden;
  bool get usable => status == FeatureStatus.available;
  bool supports(String extension) => extensions.contains(extension);
}

/// Pure resolution of [feature] for a shop and a user. Offline handling stays
/// with the screens (read cache rules); this answers only "supported" and
/// "allowed".
FeatureAvailability resolveFeature(
  AppFeature feature,
  BackendFeatures backend,
  SessionPermissions permissions,
) {
  if (!feature.requiredFeatures.every(backend.supports)) {
    return FeatureAvailability(feature, FeatureStatus.hidden);
  }
  final extensions = {
    for (final name in feature.optionalFeatures)
      if (backend.supports(name)) name,
  };
  return FeatureAvailability(
    feature,
    feature.permissions.every(permissions.allows)
        ? FeatureStatus.available
        : FeatureStatus.disabled,
    extensions: extensions,
  );
}

/// The Feature Resolver: one answer per feature for the signed-in shop and
/// user. Until `GET /meta` answers it uses [BackendFeatures.baseline].
final ProviderFamily<FeatureAvailability, AppFeature>
featureAvailabilityProvider = Provider.family<FeatureAvailability, AppFeature>(
  (ref, feature) => resolveFeature(
    feature,
    ref.watch(backendFeaturesProvider).value ?? BackendFeatures.baseline,
    ref.watch(sessionPermissionsProvider),
  ),
  name: 'featureAvailabilityProvider',
);

/// Stock workflows: counting (Update) is in every supported backend; Add and
/// Remove need `stock_movements`.
enum StockWorkflow {
  countOnly,
  countAddRemove;

  static StockWorkflow of(FeatureAvailability availability) =>
      availability.supports(BackendFeatures.stockMovements)
      ? countAddRemove
      : countOnly;
}
