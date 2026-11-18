import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/capabilities/session_permissions.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/stock_update_providers.dart';
import 'package:orange_one/shared/widgets/product_action_surface.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';

/// The Update Stock screen follows the central Feature Resolver (shop
/// support and session permission) as well as the product's own
/// permissions, the offline state and the workflow variant.
void main() {
  const barcode = '0010101010';

  Override shop(Set<String> features) => backendFeaturesProvider.overrideWith(
    (ref) async => BackendFeatures(features, confirmed: true),
  );

  final baseline = BackendFeatures.baseline.names;
  final withMovements = {...baseline, BackendFeatures.stockMovements};

  ProductDetails stock48() => ProductDetails(
    id: detailsFixture.id,
    name: detailsFixture.name,
    barcode: detailsFixture.barcode,
    price: detailsFixture.price,
    stock: 48,
    unit: detailsFixture.unit,
    version: detailsFixture.version,
    stockAdjustable: true,
    stockLocationId: 8,
    quantityDecimals: 0,
  );

  Future<(FakeDetailsRepository, ProviderContainer)> open(
    WidgetTester tester, {
    required Set<String> features,
    Map<String, bool>? permissions,
    ProductAccess access = const ProductAccess(adjustStock: true),
    List<Override> more = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeDetailsRepository()
      ..access = access
      ..product = stock48();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..restored = testSession,
          ),
          utcNowProvider.overrideWithValue(() => testNow),
          productDetailsRepositoryProvider.overrideWithValue(repo),
          shop(features),
          if (permissions != null)
            sessionPermissionsProvider.overrideWithValue(
              SessionPermissions(permissions),
            ),
          ...more,
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    container
        .read(routerProvider)
        .goNamed('productStock', queryParameters: {'barcode': barcode});
    await tester.pumpAndSettle();
    return (repo, container);
  }

  FilledButton action(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byType(ProductActionSurface),
      matching: find.byType(FilledButton),
    ),
  );

  TextField input(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('stock-count-input')));

  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('stock-count-input')), text);
    await tester.pumpAndSettle();
  }

  /// Whether the controller itself would confirm the entered quantity.
  bool confirmable(ProviderContainer container) =>
      container
          .read(stockUpdateControllerProvider(barcode).notifier)
          .confirmation() !=
      null;

  testWidgets('session permission denied: nothing can be changed', (
    tester,
  ) async {
    final (repo, container) = await open(
      tester,
      features: withMovements,
      permissions: {'product_read': true, 'stock_adjust': false},
    );
    expect(
      find.text('You do not have permission to update this stock.'),
      findsOneWidget,
    );
    expect(input(tester).enabled, isFalse);
    expect(action(tester).onPressed, isNull);
    container
        .read(stockUpdateControllerProvider(barcode).notifier)
        .changeQuantity('40');
    expect(confirmable(container), isFalse);
    expect(repo.writes, 0);
  });

  testWidgets('required backend capability missing: hidden and blocked', (
    tester,
  ) async {
    final (repo, container) = await open(
      tester,
      features: {'categories', 'product_search'},
    );
    expect(
      find.text('Stock management is not available for this shop.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stock-operation-add')), findsNothing);
    expect(input(tester).enabled, isFalse);
    expect(action(tester).onPressed, isNull);
    container
        .read(stockUpdateControllerProvider(barcode).notifier)
        .changeQuantity('40');
    expect(confirmable(container), isFalse);
    expect(repo.writes, 0);
  });

  testWidgets('allowed count-only workflow confirms and writes Update once', (
    tester,
  ) async {
    final (repo, _) = await open(
      tester,
      features: baseline,
      permissions: {'stock_adjust': true},
    );
    expect(find.byKey(const Key('stock-operation-add')), findsNothing);
    await enter(tester, '40');
    await tester.tap(find.widgetWithText(FilledButton, 'Update Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.writtenOperation, StockOperation.update);
  });

  testWidgets('allowed Add/Remove workflow writes the chosen operation', (
    tester,
  ) async {
    final (repo, _) = await open(
      tester,
      features: withMovements,
      permissions: {'stock_adjust': true},
    );
    await tester.tap(find.byKey(const Key('stock-operation-add')));
    await tester.pumpAndSettle();
    await enter(tester, '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.writtenOperation, StockOperation.add);
  });

  testWidgets('a count-only shop never confirms Add, even if requested', (
    tester,
  ) async {
    final (repo, container) = await open(tester, features: baseline);
    container.read(stockUpdateControllerProvider(barcode).notifier)
      ..changeOperation(StockOperation.add)
      ..changeQuantity('5');
    await tester.pumpAndSettle();
    expect(confirmable(container), isFalse);
    expect(repo.writes, 0);
  });

  testWidgets('per-product permission denied, even with the session allowed', (
    tester,
  ) async {
    final (repo, container) = await open(
      tester,
      features: withMovements,
      permissions: {'stock_adjust': true},
      access: const ProductAccess(),
    );
    expect(
      find.text('You do not have permission to update this stock.'),
      findsOneWidget,
    );
    expect(action(tester).onPressed, isNull);
    expect(confirmable(container), isFalse);
    expect(repo.writes, 0);
  });

  testWidgets('offline blocks confirmation; the draft is kept', (tester) async {
    final database = ReadCacheDatabase(NativeDatabase.memory());
    final cache = EncryptedReadCache(database, sessionSecret: 'stock-test');
    addTearDown(() async {
      await cache.close();
      await database.close();
    });
    cache.connectionChanged(connected: false);
    final (repo, container) = await open(
      tester,
      features: withMovements,
      more: [readCacheProvider.overrideWithValue(cache)],
    );
    await enter(tester, '40');
    expect(cache.offline, isTrue);
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(action(tester).onPressed, isNull);
    expect(confirmable(container), isFalse);
    expect(
      container.read(stockUpdateControllerProvider(barcode)).value?.draft,
      '40',
    );
    expect(repo.writes, 0);
  });

  testWidgets('busy: a second confirmation is blocked while saving', (
    tester,
  ) async {
    final (repo, container) = await open(tester, features: withMovements);
    repo.pendingWrite = Completer<ProductDetails>();
    await enter(tester, '40');
    final notifier = container.read(
      stockUpdateControllerProvider(barcode).notifier,
    );
    final confirmation = notifier.confirmation()!;
    unawaited(notifier.save(confirmation));
    await tester.pump();
    expect(
      container.read(stockUpdateControllerProvider(barcode)).value?.busy,
      isTrue,
    );
    expect(notifier.confirmation(), isNull);
    expect(action(tester).onPressed, isNull);
    await notifier.save(confirmation);
    expect(repo.writes, 1);
    // An unconfirmed outcome: never a second write, never a success.
    repo.pendingWrite!.completeError(
      const AppFailure(FailureKind.network, 'offline'),
    );
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
  });
}
