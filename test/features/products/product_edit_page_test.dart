import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
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
        const ProductEditPage(barcode: '0010101010'),
        scale: scale,
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder input() => find.byKey(const Key('product-name-input'));
  Finder action() => find.widgetWithText(FilledButton, 'Save Changes');

  /// Save Changes, then Confirm in the confirmation popup.
  Future<void> saveAndConfirm(WidgetTester tester) async {
    await tester.tap(action());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('loading state does not expose editable fields', (tester) async {
    final repo = FakeDetailsRepository()
      ..pending = Completer<ProductDetailsState>();
    await tester.pumpWidget(
      productFormApp(
        const ProductEditPage(barcode: '0010101010'),
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(input(), findsNothing);
    repo.pending!.complete(ProductDetailsState(detailsFixture, repo.access));
    await tester.pumpAndSettle();
    expect(input(), findsOneWidget);
  });

  testWidgets('rejected save keeps the draft and shows a safe error', (
    tester,
  ) async {
    final repo = FakeDetailsRepository()
      ..writeError = const AppFailure(
        FailureKind.forbidden,
        'Edit permission denied.',
      );
    await mount(tester, repo);
    await tester.enterText(input(), 'Preserved draft');
    await tester.pumpAndSettle();
    await saveAndConfirm(tester);
    expect(
      tester.widget<TextField>(input()).controller!.text,
      'Preserved draft',
    );
    expect(find.text('Edit permission denied.'), findsOneWidget);
    expect(find.text('details 0010101010'), findsNothing, reason: 'stays');
    expect(pendingSuccess(tester), isNull);
    expect(repo.writes, 1);
  });

  testWidgets('prefill, stock badge, validation, selection and success', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await mount(tester, repo);
    expect(
      tester.widget<TextField>(input()).controller!.text,
      detailsFixture.name,
    );
    expect(find.text('In stock · 48 Units'), findsOneWidget);
    // The shared name card: category, stock and tax badges; no tax card.
    expect(find.byKey(const Key('product-category-badge')), findsOneWidget);
    expect(find.byKey(const Key('product-tax-row')), findsOneWidget);
    expect(find.byKey(const Key('product-hero-barcode')), findsOneWidget);
    expect(find.byTooltip('Edit product name'), findsNothing);
    expect(find.byTooltip('Update stock'), findsNothing);
    expect(find.textContaining('Powered'), findsNothing);
    expect(tester.widget<FilledButton>(action()).onPressed, isNull);
    await tester.enterText(input(), '');
    await tester.pumpAndSettle();
    expect(find.text('Product name is required.'), findsOneWidget);
    await tester.enterText(input(), 'Aachi 100g');
    await tester.ensureVisible(find.byKey(const Key('product-tax-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-tax-input')));
    await tester.pumpAndSettle();
    expect(find.text('Select Tax'), findsOneWidget);
    await tester.tap(find.text('VAT (15%)'));
    await tester.pumpAndSettle();
    await tester.tap(action());
    await tester.pumpAndSettle();
    expect(find.text('Confirm changes'), findsOneWidget);
    expect(find.textContaining('Name: Aachi 100g'), findsOneWidget);
    expect(find.textContaining('Tax: VAT (15%)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0, reason: 'cancel never saves');
    expect(
      tester.widget<TextField>(input()).controller!.text,
      'Aachi 100g',
      reason: 'draft kept',
    );
    await saveAndConfirm(tester);
    expect(repo.writtenTaxIds, [1]);
    expect(repo.writes, 1);
    // Success returns to Product Details with the success toast.
    expect(find.text('details 0010101010'), findsOneWidget);
    final success = pendingSuccess(tester)!;
    expect(success.title, 'Product name and tax updated successfully');
    expect(success.message, 'New name: Aachi 100g · Tax: VAT (15%)');
    expect(tester.takeException(), isNull);
  });
  testWidgets('tax sheet dismissal does not remove current assignments', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await mount(tester, repo);
    await tester.ensureVisible(find.byKey(const Key('product-tax-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-tax-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close tax selection'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(action()).onPressed, isNull);
    expect(repo.writes, 0);
  });
  testWidgets('busy save disables input and repeated saves', (tester) async {
    final repo = FakeDetailsRepository()
      ..pendingWrite = Completer<ProductDetails>();
    await mount(tester, repo);
    await tester.enterText(input(), 'Changed');
    await tester.pumpAndSettle();
    await saveAndConfirm(tester);
    expect(find.text('Updating…'), findsOneWidget);
    expect(tester.widget<TextField>(input()).enabled, isFalse);
    expect(repo.writes, 1);
    repo.pendingWrite!.complete(detailsFixture);
    await tester.pumpAndSettle();
  });
  testWidgets('missing product, denied access and initial errors', (
    tester,
  ) async {
    final repo = FakeDetailsRepository()..product = null;
    await mount(tester, repo);
    expect(find.text('Product not found'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    repo
      ..product = detailsFixture
      ..access = const ProductAccess();
    await mount(tester, repo);
    expect(
      find.text('You do not have permission to edit this product.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(input()).enabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.error = const AppFailure(
      FailureKind.network,
      'Connection unavailable.',
    );
    await mount(tester, repo);
    expect(find.text('Connection unavailable.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('fixed navigation and glass actions fit $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, FakeDetailsRepository(), scale: 1.6);
      final header = tester.getTopLeft(find.text('Edit Name & Tax'));
      final footer = tester.getTopLeft(action());
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Edit Name & Tax')), header);
      expect(tester.getTopLeft(action()), footer);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        input(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(input());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('category picker selects, saves and dismisses safely', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await mount(tester, repo);
    final field = find.byKey(const Key('product-category-input'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: field, matching: find.text('Spices')),
      findsOneWidget,
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close category selection'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(action()).onPressed, isNull);

    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('Select Category'), findsOneWidget);
    await tester.tap(find.text('Drinks'));
    await tester.pumpAndSettle();
    await saveAndConfirm(tester);
    expect(repo.writtenCategory?.id, 5);
    expect(pendingSuccess(tester)?.title, 'Category updated successfully');
    expect(pendingSuccess(tester)?.message, 'Category: Drinks');
  });

  testWidgets('a category added in the picker is selected for the product', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await mount(tester, repo);
    final field = find.byKey(const Key('product-category-input'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-new-input')),
      'Snacks',
    );
    await tester.tap(find.byKey(const Key('category-add-button')));
    await tester.pumpAndSettle();
    expect(repo.categoryCreates, 1);
    expect(
      find.descendant(of: field, matching: find.text('Snacks')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(action()).onPressed, isNotNull);
    await saveAndConfirm(tester);
    expect(repo.writtenCategory?.id, 101);
  });

  testWidgets('no category creation without permission', (tester) async {
    final repo = FakeDetailsRepository()
      ..access = const ProductAccess(
        editName: true,
        readReferences: true,
        updateCategory: true,
      );
    await mount(tester, repo);
    final field = find.byKey(const Key('product-category-input'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.byKey(const Key('category-add-button')), findsNothing);
  });

  testWidgets('without category permission the field is read-only', (
    tester,
  ) async {
    final repo = FakeDetailsRepository()
      ..access = const ProductAccess(
        editName: true,
        readReferences: true,
        updateTaxes: true,
      );
    await mount(tester, repo);
    final field = find.byKey(const Key('product-category-input'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('Select Category'), findsNothing);
  });
}
