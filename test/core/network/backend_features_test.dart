import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/backend_features.dart';

/// `GET /meta` `data` of environment A (older addons, POS machine).
const Map<String, Object?> _olderShop = {
  'api_version': '1.0.0',
  'min_app_version': '0.0.0',
  'features': [
    'categories',
    'category_create',
    'product_changes',
    'product_history',
    'product_search',
    'stock_adjustments',
    'telemetry',
  ],
  'supported_locales': ['en_US', 'fr_CH', 'de_CH', 'it_IT'],
  'maintenance': null,
};

/// `GET /meta` `data` of environment B (newer addons, development laptop).
const Map<String, Object?> _newerShop = {
  'api_version': '1.0.0',
  'min_app_version': '0.0.0',
  'features': [
    'categories',
    'category_create',
    'product_changes',
    'product_history',
    'product_search',
    'stock_adjustments',
    'stock_movements',
    'telemetry',
  ],
  'supported_locales': ['en_US'],
  'maintenance': null,
};

void main() {
  test('an older shop has no stock movements', () {
    final features = BackendFeatures.fromMeta(_olderShop);
    expect(features.supports(BackendFeatures.stockMovements), isFalse);
    expect(features.supports('stock_adjustments'), isTrue);
    expect(features.apiVersion, '1.0.0');
  });

  test('a newer shop has stock movements', () {
    expect(
      BackendFeatures.fromMeta(_newerShop)
          .supports(BackendFeatures.stockMovements),
      isTrue,
    );
  });

  test('unknown future features are kept and harmless', () {
    final features = BackendFeatures.fromMeta({
      ..._newerShop,
      'features': [...?(_newerShop['features'] as List?), 'future_feature'],
    });
    expect(features.supports('future_feature'), isTrue);
    expect(features.supports(BackendFeatures.stockMovements), isTrue);
  });

  test('the baseline is what the oldest supported addon offers', () {
    final older = BackendFeatures.fromMeta(_olderShop).names;
    // Everything assumed without /meta exists on the oldest shop.
    expect(older.containsAll(BackendFeatures.baseline.names), isTrue);
    expect(
      BackendFeatures.baseline.supports(BackendFeatures.stockMovements),
      isFalse,
    );
  });

  test('an unexpected reply is a protocol failure', () {
    for (final data in <Object?>[
      null,
      'text',
      <String, Object?>{},
      {'features': 'stock_movements'},
      {
        'features': ['stock_movements', 3],
      },
    ]) {
      expect(
        () => BackendFeatures.fromMeta(data),
        throwsA(
          isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.protocol),
        ),
        reason: '$data',
      );
    }
  });
}
