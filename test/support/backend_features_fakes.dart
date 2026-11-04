import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:orange_one/core/network/backend_features.dart';

/// A shop whose backend advertises stock movements (Add and Remove).
final Override stockMovementsBackend = backendFeaturesProvider.overrideWith(
  (ref) async => BackendFeatures({
    ...BackendFeatures.baseline.names,
    BackendFeatures.stockMovements,
  }),
);
