import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

import '../../support/product_details_fakes.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeDetailsRepository repo, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: OrangeTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ProductEditPage(barcode: '0010101010'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder input() => find.byKey(const Key('product-name-input'));
  Finder action() => find.widgetWithText(FilledButton, 'Save Changes');

  testWidgets('loading state does not expose editable fields', (tester) async {
    final repo = FakeDetailsRepository()
      ..pending = Completer<ProductDetailsState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ProductEditPage(barcode: '0010101010')),
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
    await tester.tap(action());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input()).controller!.text,
      'Preserved draft',
    );
    expect(find.text('Edit permission denied.'), findsOneWidget);
    expect(find.text('Name & Tax Updated Successfully'), findsNothing);
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
    expect(repo.writtenTaxIds, [1]);
    expect(repo.writes, 1);
    expect(find.text('Name & Tax Updated Successfully'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(tester.widget<TextField>(input()).enabled, isFalse);
    expect(find.text('In stock · 48 Units'), findsOneWidget);
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
    await tester.tap(action());
    await tester.pumpAndSettle();
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
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Edit Name & Tax')), header);
      expect(tester.getTopLeft(action()), footer);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(input());
      await tester.pumpAndSettle();
      await tester.tap(input());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
