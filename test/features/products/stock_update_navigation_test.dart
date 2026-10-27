import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_stock_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';

void main() {
  test('stock route is guarded during restore and after logout', () {
    expect(
      authenticationRedirect(const AsyncLoading(), '/home/products/stock'),
      '/startup',
    );
    expect(
      authenticationRedirect(const AsyncData(null), '/home/products/stock'),
      '/login',
    );
    expect(
      authenticationRedirect(AsyncData(testSession), '/home/products/stock'),
      isNull,
    );
  });

  Future<ProviderContainer> openDetails(
    WidgetTester tester,
    FakeDetailsRepository repo,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..restored = testSession,
          ),
          utcNowProvider.overrideWithValue(() => testNow),
          productDetailsRepositoryProvider.overrideWithValue(repo),
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
        .goNamed('productDetails', queryParameters: {'barcode': '0010101010'});
    await tester.pumpAndSettle();
    return container;
  }

  IconButton stockAction(WidgetTester tester) => tester.widget<IconButton>(
    find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Update stock',
    ),
  );

  testWidgets('details opens Update Stock; a confirmed count is shown', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    final container = await openDetails(tester, repo);
    expect(find.byType(ProductDetailsPage), findsOneWidget);
    expect(find.textContaining('In stock · 48'), findsOneWidget);
    await tester.tap(find.byTooltip('Update stock'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductStockUpdatePage), findsOneWidget);
    expect(find.text('48 Units'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('stock-count-input')), '50');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update Stock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Difference: +2 Units'), findsOneWidget);
    expect(repo.writes, 0);
    await tester.tap(find.text('Confirm update'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.writtenCount?.text, '50');
    expect(find.text('Stock Updated Successfully'), findsOneWidget);
    expect(
      find.text('Previous stock: 48 Units · New stock: 50 Units'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/home/products/details',
    );
    expect(find.textContaining('In stock · 50'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation never writes', (tester) async {
    final repo = FakeDetailsRepository();
    await openDetails(tester, repo);
    await tester.tap(find.byTooltip('Update stock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stock-count-input')), '7');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
  });

  for (final (label, access, adjustable, stock) in [
    ('without permission', const ProductAccess(updatePrice: true), true, 48.0),
    ('for packaged or owner stock', null, false, 48.0),
    ('for untracked stock', null, false, null),
  ]) {
    testWidgets('the stock action is disabled $label', (tester) async {
      final repo = FakeDetailsRepository();
      if (access != null) repo.access = access;
      repo.product = ProductDetails(
        id: detailsFixture.id,
        name: detailsFixture.name,
        barcode: detailsFixture.barcode,
        price: detailsFixture.price,
        stock: stock,
        unit: detailsFixture.unit,
        version: detailsFixture.version,
        stockAdjustable: adjustable,
        stockLocationId: 8,
      );
      await openDetails(tester, repo);
      expect(stockAction(tester).onPressed, isNull);
    });
  }
}
