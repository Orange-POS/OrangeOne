import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/capabilities/api_contract.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/core/capabilities/feature_resolver.dart';
import 'package:orange_one/core/capabilities/session_permissions.dart';
import 'package:orange_one/core/network/backend_features.dart';

BackendFeatures _shop(Set<String> names, {String? apiVersion = '1.0.0'}) =>
    BackendFeatures(names, apiVersion: apiVersion, confirmed: true);

void main() {
  group('API contract', () {
    test('1.x and an unknown version use the v1 adapters', () {
      for (final version in [null, '1.0.0', '1.7.3']) {
        final resolution = resolveApiContract(version);
        expect(resolution.contract, ApiContract.mobileV1, reason: version);
        expect(resolution.mismatch, isNull);
      }
    });

    test('a newer major needs a newer app; older or unreadable, a newer '
        'server', () {
      expect(
        resolveApiContract('2.0.0').mismatch,
        ContractMismatch.backendNewer,
      );
      for (final version in ['0.9.0', 'v1', '']) {
        expect(
          resolveApiContract(version).mismatch,
          ContractMismatch.backendOlder,
          reason: version,
        );
      }
    });
  });

  group('compatibility', () {
    test('a confirmed 1.x shop is compatible', () {
      expect(
        resolveCompatibility(_shop({'stock_adjustments'})),
        CompatibilityStatus.compatible,
      );
    });

    test('refusals block', () {
      expect(
        resolveCompatibility(
          BackendFeatures.refused(BackendRefusal.appUpgradeRequired),
        ),
        CompatibilityStatus.appUpgradeRequired,
      );
      expect(
        resolveCompatibility(
          BackendFeatures.refused(BackendRefusal.maintenance),
        ),
        CompatibilityStatus.maintenance,
      );
    });

    test('contract mismatches block only when confirmed by the shop', () {
      expect(
        resolveCompatibility(_shop({}, apiVersion: '2.0.0')),
        CompatibilityStatus.appUpgradeRequired,
      );
      expect(
        resolveCompatibility(_shop({}, apiVersion: '0.1.0')),
        CompatibilityStatus.backendUnsupported,
      );
      // The unconfirmed baseline (pending, offline, unreadable) never blocks.
      expect(
        resolveCompatibility(BackendFeatures.baseline),
        CompatibilityStatus.compatible,
      );
    });

    test('the provider is compatible while /meta is pending', () async {
      final container = ProviderContainer.test(
        overrides: [
          backendFeaturesProvider.overrideWith(
            (ref) => Future<BackendFeatures>.delayed(
              const Duration(milliseconds: 10),
              () => BackendFeatures.refused(BackendRefusal.maintenance),
            ),
          ),
        ],
      );
      final status = container.listen(compatibilityProvider, (_, _) {});
      expect(status.read(), CompatibilityStatus.compatible);
      await container.read(backendFeaturesProvider.future);
      expect(
        container.read(compatibilityProvider),
        CompatibilityStatus.maintenance,
      );
    });
  });

  group('Feature Resolver', () {
    test('hidden when the shop lacks a required feature', () {
      final availability = resolveFeature(
        AppFeature.productHistory,
        _shop({'stock_adjustments'}),
        SessionPermissions.unknown,
      );
      expect(availability.status, FeatureStatus.hidden);
      expect(availability.visible, isFalse);
    });

    test('disabled when a reported permission is missing', () {
      final availability = resolveFeature(
        AppFeature.stockUpdate,
        _shop({'stock_adjustments'}),
        const SessionPermissions({'stock_adjust': false, 'product_read': true}),
      );
      expect(availability.status, FeatureStatus.disabled);
      expect(availability.usable, isFalse);
    });

    test('a key an older backend does not report counts as not granted', () {
      final availability = resolveFeature(
        AppFeature.stockUpdate,
        _shop({'stock_adjustments'}),
        const SessionPermissions({'product_read': true}),
      );
      expect(availability.status, FeatureStatus.disabled);
    });

    test('unknown permissions never restrict (the server enforces them)', () {
      final availability = resolveFeature(
        AppFeature.stockUpdate,
        _shop({'stock_adjustments'}),
        SessionPermissions.unknown,
      );
      expect(availability.status, FeatureStatus.available);
    });

    test('stock workflow variants follow stock_movements', () {
      final countOnly = resolveFeature(
        AppFeature.stockUpdate,
        BackendFeatures.baseline,
        SessionPermissions.unknown,
      );
      final full = resolveFeature(
        AppFeature.stockUpdate,
        _shop({'stock_adjustments', BackendFeatures.stockMovements}),
        const SessionPermissions({'stock_adjust': true}),
      );
      expect(StockWorkflow.of(countOnly), StockWorkflow.countOnly);
      expect(StockWorkflow.of(full), StockWorkflow.countAddRemove);
      expect(full.usable, isTrue);
    });

    test('the provider combines the shop and the user', () async {
      final container = ProviderContainer.test(
        overrides: [
          backendFeaturesProvider.overrideWith(
            (ref) async =>
                _shop({'stock_adjustments', BackendFeatures.stockMovements}),
          ),
          sessionPermissionsProvider.overrideWithValue(
            const SessionPermissions({'stock_adjust': true}),
          ),
        ],
      );
      final provider = featureAvailabilityProvider(AppFeature.stockUpdate);
      container.listen(provider, (_, _) {});
      // Baseline until /meta answers: Update only.
      expect(
        StockWorkflow.of(container.read(provider)),
        StockWorkflow.countOnly,
      );
      await container.read(backendFeaturesProvider.future);
      expect(
        StockWorkflow.of(container.read(provider)),
        StockWorkflow.countAddRemove,
      );
    });
  });
}
