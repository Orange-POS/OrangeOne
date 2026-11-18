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

/// Identity the compatibility and capability decisions belong to: the
/// signed-in session (sign-in method, backend, company, user and session)
/// or the Demo Mode sample. Null while signed out. App composition binds it;
/// a different value is a session or backend replacement.
final Provider<Object?> capabilityScopeProvider = Provider<Object?>(
  (ref) => null,
  name: 'capabilityScopeProvider',
);

/// The last definitive blocking answer of one [capabilityScopeProvider]
/// identity. Container-lived and written only by [compatibilityProvider].
class _ConfirmedBlock {
  Object? scope;
  CompatibilityStatus? status;
}

final Provider<_ConfirmedBlock> _confirmedBlockProvider =
    Provider<_ConfirmedBlock>(
      (ref) => _ConfirmedBlock(),
      name: '_confirmedBlockProvider',
    );

/// Compatibility of the signed-in shop; compatible while `/meta` is pending
/// and without a session.
///
/// A confirmed refusal (upgrade required, maintenance, unsupported contract)
/// stays in force for the same session and backend until the shop confirms
/// compatibility: a retry that fails (network, timeout, unreadable reply)
/// only yields the unconfirmed baseline, which never lifts it. Values read
/// while `/meta` is (re)loading are ignored, so a previous session's answer
/// cannot leak into a replacement session, and a new [capabilityScopeProvider]
/// identity starts without a block.
final Provider<CompatibilityStatus> compatibilityProvider =
    Provider<CompatibilityStatus>((ref) {
      final scope = ref.watch(capabilityScopeProvider);
      final block = ref.watch(_confirmedBlockProvider);
      if (block.scope != scope) {
        block
          ..scope = scope
          ..status = null;
      }
      final async = ref.watch(backendFeaturesProvider);
      final features = async.isLoading ? null : async.value;
      if (features == null || !features.confirmed) {
        return block.status ?? CompatibilityStatus.compatible;
      }
      final status = resolveCompatibility(features);
      block.status = status.blocked ? status : null;
      return status;
    }, name: 'compatibilityProvider');
