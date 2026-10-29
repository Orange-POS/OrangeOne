import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/presentation/pages/product_stock_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';

class _Unset extends UnsetStockController {
  @override
  Set<int> build() => const {10};
}

/// Update, Add and Remove on the stock screen (stock 48 Units).
void main() {
  Future<FakeDetailsRepository> openStock(
    WidgetTester tester, {
    FakeDetailsRepository? repository,
    bool direct = false,
    List<Override> more = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = repository ?? FakeDetailsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..restored = testSession,
          ),
          utcNowProvider.overrideWithValue(() => testNow),
          productDetailsRepositoryProvider.overrideWithValue(repo),
          ...more,
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(tester.element(find.byType(App)))
        .read(routerProvider);
    const query = {'barcode': '0010101010'};
    if (direct) {
      router.goNamed('productStock', queryParameters: query);
      await tester.pumpAndSettle();
      return repo;
    }
    router.goNamed('productDetails', queryParameters: query);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Update stock'));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> select(WidgetTester tester, StockOperation operation) async {
    await tester.tap(find.byKey(Key('stock-operation-${operation.name}')));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('stock-count-input')), text);
    await tester.pumpAndSettle();
  }

  FilledButton action(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  ProductDetails stockOf(double? stock, {bool adjustable = true}) =>
      ProductDetails(
        id: detailsFixture.id,
        name: detailsFixture.name,
        barcode: detailsFixture.barcode,
        price: detailsFixture.price,
        stock: stock,
        unit: detailsFixture.unit,
        version: detailsFixture.version,
        stockAdjustable: adjustable,
        stockLocationId: 8,
        quantityDecimals: 0,
      );

  testWidgets('the selector offers Update, Add and Remove; Update is first', (
    tester,
  ) async {
    await openStock(tester);
    for (final label in ['Update', 'Add', 'Remove']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Counted Quantity'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update Stock'), findsOneWidget);
    Color? fill(StockOperation operation) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byKey(Key('stock-operation-${operation.name}')),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;
    expect(fill(StockOperation.update), OrangeTheme.pale);
    expect(fill(StockOperation.add), Colors.white);
    await select(tester, StockOperation.add);
    expect(fill(StockOperation.add), OrangeTheme.pale);
    expect(fill(StockOperation.update), Colors.white);
  });

  testWidgets('switching modes changes the label, helper and button', (
    tester,
  ) async {
    await openStock(tester);
    await select(tester, StockOperation.add);
    expect(find.text('Quantity to add'), findsOneWidget);
    expect(find.text('Increases the current stock.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add Stock'), findsOneWidget);

    await select(tester, StockOperation.remove);
    expect(find.text('Quantity to remove'), findsOneWidget);
    expect(find.textContaining('cannot go below zero'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Remove Stock'), findsOneWidget);

    await select(tester, StockOperation.update);
    expect(find.text('Counted Quantity'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update Stock'), findsOneWidget);
  });

  testWidgets('the preview shows the stock each operation would give', (
    tester,
  ) async {
    await openStock(tester);
    expect(find.byKey(const Key('stock-preview')), findsNothing);

    await enter(tester, '40');
    expect(find.text('New stock: 40 Units'), findsOneWidget);

    await select(tester, StockOperation.add);
    expect(find.text('48 + 40 = 88 Units'), findsOneWidget);

    await select(tester, StockOperation.remove);
    expect(find.text('48 − 40 = 8 Units'), findsOneWidget);

    await enter(tester, '41');
    expect(find.text('48 − 41 = 7 Units'), findsOneWidget);
  });

  testWidgets('the button stays disabled until the quantity is valid', (
    tester,
  ) async {
    await openStock(
      tester,
      repository: FakeDetailsRepository()..product = stockOf(48),
    );
    await select(tester, StockOperation.add);
    expect(action(tester, 'Add Stock').onPressed, isNull);

    for (final (input, message) in [
      ('0', 'Enter a quantity greater than zero.'),
      ('abc', 'Enter a valid number.'),
      ('-5', 'Enter a valid number.'),
      ('1.5', 'Enter a whole number for this unit.'),
    ]) {
      await enter(tester, input);
      expect(find.text(message), findsOneWidget, reason: input);
      expect(action(tester, 'Add Stock').onPressed, isNull, reason: input);
      expect(find.byKey(const Key('stock-preview')), findsNothing);
    }
    await enter(tester, '5');
    expect(action(tester, 'Add Stock').onPressed, isNotNull);
  });

  testWidgets('removing more than the stock is refused', (tester) async {
    await openStock(tester);
    await select(tester, StockOperation.remove);
    await enter(tester, '49');
    expect(
      find.text('You cannot remove more than the current stock (48 Units).'),
      findsOneWidget,
    );
    expect(action(tester, 'Remove Stock').onPressed, isNull);

    await enter(tester, '48');
    expect(find.text('48 − 48 = 0 Units'), findsOneWidget);
    expect(action(tester, 'Remove Stock').onPressed, isNotNull);
  });

  testWidgets('a quantity kept across modes is checked for the new mode', (
    tester,
  ) async {
    await openStock(tester);
    await enter(tester, '60');
    expect(action(tester, 'Update Stock').onPressed, isNotNull);

    await select(tester, StockOperation.remove);
    expect(find.textContaining('cannot remove more'), findsOneWidget);
    expect(action(tester, 'Remove Stock').onPressed, isNull);

    await select(tester, StockOperation.add);
    expect(find.text('48 + 60 = 108 Units'), findsOneWidget);
    expect(action(tester, 'Add Stock').onPressed, isNotNull);
  });

  for (final (operation, input, button, confirmed, stock, shown) in [
    (
      StockOperation.add,
      '40',
      'Add Stock',
      'Add: 40 Units\nNew stock: 88 Units',
      88.0,
      'Previous stock: 48 Units · New stock: 88 Units',
    ),
    (
      StockOperation.remove,
      '40',
      'Remove Stock',
      'Remove: 40 Units\nNew stock: 8 Units',
      8.0,
      'Previous stock: 48 Units · New stock: 8 Units',
    ),
    (
      StockOperation.update,
      '40',
      'Update Stock',
      'Difference: -8 Units',
      40.0,
      'Previous stock: 48 Units · New stock: 40 Units',
    ),
  ]) {
    testWidgets('${operation.name}: confirm, write once, success toast', (
      tester,
    ) async {
      final repo = await openStock(tester);
      await select(tester, operation);
      await enter(tester, input);
      await tester.tap(find.widgetWithText(FilledButton, button));
      await tester.pumpAndSettle();
      expect(find.textContaining(confirmed), findsOneWidget);
      expect(repo.writes, 0, reason: 'nothing is sent before Confirm');

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(repo.writtenOperation, operation);
      expect(repo.writtenCount?.text, input);
      expect(repo.writtenVersions, ['3']);
      expect(find.byType(ProductStockUpdatePage), findsNothing);
      expect(find.text('Stock Updated Successfully'), findsOneWidget);
      expect(find.text(shown), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      // Product Details shows the refreshed stock.
      expect(
        find.textContaining('In stock · ${stock.toInt()}'),
        findsOneWidget,
      );
    });
  }

  testWidgets('a saved count clears the not-set flag of that product', (
    tester,
  ) async {
    await openStock(
      tester,
      more: [unsetStockProvider.overrideWith(_Unset.new)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    expect(container.read(unsetStockProvider), {10});
    await enter(tester, '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Update Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(container.read(unsetStockProvider), isEmpty);
  });

  testWidgets('a version conflict stays on the screen and writes once', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await openStock(tester, repository: repo);
    await select(tester, StockOperation.add);
    await enter(tester, '5');
    repo.writeError = const AppFailure(
      FailureKind.conflict,
      'This product was changed on another device.',
      code: 'VERSION_CONFLICT',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(find.byType(ProductStockUpdatePage), findsOneWidget);
    expect(find.textContaining('another device'), findsOneWidget);
    expect(find.text('Stock Updated Successfully'), findsNothing);
    // The mode and the quantity are kept for another review.
    expect(find.text('Quantity to add'), findsOneWidget);
    expect(action(tester, 'Add Stock').onPressed, isNotNull);
  });

  testWidgets(
    'a network error blocks a second write until the stock is checked',
    (tester) async {
      final repo = FakeDetailsRepository();
      await openStock(tester, repository: repo);
      await select(tester, StockOperation.remove);
      await enter(tester, '5');
      repo.writeError = const AppFailure(FailureKind.network, 'Offline.');
      await tester.tap(find.widgetWithText(FilledButton, 'Remove Stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Check current stock'),
        findsOneWidget,
      );
      // The mode cannot change while the outcome is unknown.
      await tester.tap(find.byKey(const Key('stock-operation-add')));
      await tester.pumpAndSettle();
      expect(find.text('Quantity to remove'), findsOneWidget);
      expect(repo.writes, 1);
    },
  );

  testWidgets('a backend rule is shown and the screen stays editable', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await openStock(tester, repository: repo);
    await select(tester, StockOperation.remove);
    await enter(tester, '5');
    repo.writeError = const AppFailure(
      FailureKind.validation,
      'There is not enough stock to remove this quantity.',
      code: 'BUSINESS_RULE_VIOLATION',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not enough stock'), findsOneWidget);
    expect(action(tester, 'Remove Stock').onPressed, isNotNull);
  });

  testWidgets('without permission nothing can be changed', (tester) async {
    final repo = FakeDetailsRepository()
      ..access = const ProductAccess()
      ..product = stockOf(48);
    await openStock(tester, repository: repo, direct: true);
    expect(
      find.text('You do not have permission to update this stock.'),
      findsOneWidget,
    );
    expect(action(tester, 'Update Stock').onPressed, isNull);
    final tile = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('stock-operation-add')),
        matching: find.byType(InkWell),
      ),
    );
    expect(tile.onTap, isNull);
    expect(repo.writes, 0);
  });
}
