import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/network/backend_features.dart';

/// Mobile API contracts this app has adapters for. App composition binds
/// each one to its data implementations; pages never see the contract.
enum ApiContract {
  /// `/api/orangeone/mobile/v1`, `api_version` 1.x (additive changes only).
  mobileV1,
}

/// Why a backend's `api_version` cannot be served by this app.
enum ContractMismatch {
  /// A newer major contract than this app knows: the app must be updated.
  backendNewer,

  /// An older or unreadable major contract: the server must be updated.
  backendOlder,
}

/// The contract for a backend, or why there is none.
class ContractResolution {
  const new supported(ApiContract this.contract) : mismatch = null;
  const new unsupported(ContractMismatch this.mismatch) : contract = null;

  final ApiContract? contract;
  final ContractMismatch? mismatch;
}

/// Selects the adapter set from `GET /meta` `api_version` (major version).
///
/// An unknown version (no `/meta` answer yet, the baseline) is served with
/// [ApiContract.mobileV1], the contract every supported addon implements.
ContractResolution resolveApiContract(String? apiVersion) {
  if (apiVersion == null) {
    return const ContractResolution.supported(ApiContract.mobileV1);
  }
  final major = int.tryParse(
    RegExp(r'^(\d+)\.').firstMatch(apiVersion)?.group(1) ?? '',
  );
  return switch (major) {
    1 => const ContractResolution.supported(ApiContract.mobileV1),
    final int value when value > 1 => const ContractResolution.unsupported(
      ContractMismatch.backendNewer,
    ),
    _ => const ContractResolution.unsupported(ContractMismatch.backendOlder),
  };
}

/// The contract whose adapters serve the signed-in shop. A mismatch keeps
/// [ApiContract.mobileV1] bound (the compatibility check blocks the screens),
/// so dependents are only rebuilt when the contract really changes.
final Provider<ApiContract> apiContractProvider = Provider<ApiContract>((ref) {
  final features =
      ref.watch(backendFeaturesProvider).value ?? BackendFeatures.baseline;
  return resolveApiContract(features.apiVersion).contract ??
      ApiContract.mobileV1;
}, name: 'apiContractProvider');
