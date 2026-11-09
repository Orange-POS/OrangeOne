import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/capabilities/api_contract.dart';
import 'package:orange_one/core/network/backend_features.dart';

/// Whether the signed-in shop's backend can be used with this app.
enum CompatibilityStatus {
  compatible,

  /// The shop requires a newer app (`APP_UPGRADE_REQUIRED`, or a newer major
  /// API contract than this app knows).
  appUpgradeRequired,

  /// The shop's server is too old for this app.
  backendUnsupported,

  /// The shop's server is under maintenance.
  maintenance;

  bool get blocked => this != compatible;
}

/// Derives the status from the shop's `GET /meta`. Only definitive answers
/// block: an unconfirmed baseline (pending, offline or unreadable `/meta`)
/// is always compatible, so the app degrades instead of locking users out.
CompatibilityStatus resolveCompatibility(BackendFeatures features) {
  switch (features.refusal) {
    case BackendRefusal.appUpgradeRequired:
      return CompatibilityStatus.appUpgradeRequired;
    case BackendRefusal.maintenance:
      return CompatibilityStatus.maintenance;
    case null:
      break;
  }
  if (!features.confirmed) return CompatibilityStatus.compatible;
  return switch (resolveApiContract(features.apiVersion).mismatch) {
    null => CompatibilityStatus.compatible,
    ContractMismatch.backendNewer => CompatibilityStatus.appUpgradeRequired,
    ContractMismatch.backendOlder => CompatibilityStatus.backendUnsupported,
  };
}

/// Compatibility of the signed-in shop; compatible while `/meta` is pending
/// and without a session.
final Provider<CompatibilityStatus> compatibilityProvider =
    Provider<CompatibilityStatus>((ref) {
      final features = ref.watch(backendFeaturesProvider).value;
      return features == null
          ? CompatibilityStatus.compatible
          : resolveCompatibility(features);
    }, name: 'compatibilityProvider');
