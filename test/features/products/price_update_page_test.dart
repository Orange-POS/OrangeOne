import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/product_details_fakes.dart';
import '../../support/product_router.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeDetailsRepository repo, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      productFormApp(
        const ProductPriceUpdatePage(barcode: '0010101010'),
        scale: scale,
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder getInput() => find.byKey(const Key('new-price-input'));
  Finder getAction() => find.widgetWithText(FilledButton, 'Save Changes');

  testWidgets('empty and invalid CHF field disable updates', (tester) async {
    final repo = FakeDetailsRepository();
    await mount(tester, repo);
    expect(find.text('CHF 100.00'), findsOneWidget);
    expect(find.text('In stock · 48 Units'), findsOneWidget);
    // The shared name card: category and tax badges with the stock badge.
    expect(find.byKey(const Key('product-category-badge')), findsOneWidget);
    expect(find.byKey(const Key('product-tax-badge')), findsOneWidget);
    expect(find.byTooltip('Edit product name'), findsNothing);
    expect(find.byTooltip('Update stock'), findsNothing);
    expect(find.textContaining('Powered'), findsNothing);
    expect(tester.widget<FilledButton>(getAction()).onPressed, isNull);
    await tester.enterText(getInput(), 'AAA');
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a valid price'), findsOneWidget);
    expect(tester.widget<FilledButton>(getAction()).onPressed, isNull);
    expect(repo.writes, 0);
  });

  testWidgets(
    'confirmation can cancel, then save renders acknowledged success',
    (tester) async {
      final repo = FakeDetailsRepository();
      await mount(tester, repo);
      await tester.enterText(getInput(), '125.00');
      await tester.pumpAndSettle();
      await tester.tap(getAction());
      await tester.pumpAndSettle();
      expect(find.textContaining('New price: CHF 125.00'), findsOneWidget);
      expect(repo.writes, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      expect(tester.widget<TextField>(getInput()).controller!.text, '125.00');
      await tester.tap(getAction());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      // Success returns to Product Details, which shows the toast.
      expect(find.text('details 0010101010'), findsOneWidget);
      final success = pendingSuccess(tester)!;
      expect(success.title, 'Price Updated Successfully');
      expect(success.message, 'New price: CHF 125.00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving freezes the input and back navigation', (tester) async {
    final repo = FakeDetailsRepository()
      ..pendingWrite = Completer<ProductDetails>();
    await mount(tester, repo);
    await tester.enterText(getInput(), '125');
    await tester.pumpAndSettle();
    await tester.tap(getAction());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Updating…'), findsOneWidget);
    expect(tester.widget<TextField>(getInput()).enabled, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Back',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(repo.writes, 1);
    repo.pendingWrite!.complete(detailsFixture);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied and missing products cannot update', (tester) async {
    final repo = FakeDetailsRepository()..access = const ProductAccess();
    await mount(tester, repo);
    expect(
      find.text('You do not have permission to update this price.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(getInput()).enabled, isFalse);
    expect(tester.widget<FilledButton>(getAction()).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    repo.product = null;
    await mount(tester, repo);
    expect(find.text('Product not found'), findsOneWidget);
    expect(getInput(), findsNothing);
  });

  testWidgets(
    'failed writes preserve input and offer a safe current-price check',
    (tester) async {
      final repo = FakeDetailsRepository()
        ..writeError = const AppFailure(FailureKind.network, 'Fixture network');
      await mount(tester, repo);
      await tester.enterText(getInput(), '125.00');
      await tester.pumpAndSettle();
      await tester.tap(getAction());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('save could not be confirmed'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(getInput()).controller!.text, '125.00');
      expect(find.textContaining('Price Updated Successfully'), findsNothing);
      expect(find.text('Details 0010101010'), findsNothing);
      await tester.tap(find.text('Check current price'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(tester.widget<TextField>(getInput()).controller!.text, '125.00');
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('price page fixed controls and keyboard fit $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, FakeDetailsRepository(), scale: 1.6);
      final top = tester.getTopLeft(find.byTooltip('Back'));
      final bottom = tester.getTopLeft(getAction());
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byTooltip('Back')), top);
      expect(tester.getTopLeft(getAction()), bottom);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      // The taller name card pushes the field down: scroll to it.
      await tester.scrollUntilVisible(
        getInput(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(getInput(), '125.00');
      await tester.pumpAndSettle();
      expect(getAction().hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
