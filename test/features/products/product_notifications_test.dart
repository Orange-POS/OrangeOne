import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_stock_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/product_details_fakes.dart';
import '../../support/product_router.dart';

/// Success and error notifications of the product screens: a success names
/// only the fields that were changed and saved, and a failure never shows one.
void main() {
  Future<FakeDetailsRepository> mount(
    WidgetTester tester,
    Widget page, {
    FakeDetailsRepository? repository,
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = repository ?? FakeDetailsRepository();
    await tester.pumpWidget(
      productFormApp(
        page,
        locale: locale,
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> confirmSave(WidgetTester tester, String button) async {
    await tester.tap(find.widgetWithText(FilledButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  const edit = ProductEditPage(barcode: '0010101010');
  final name = find.byKey(const Key('product-name-input'));

  Future<void> rename(WidgetTester tester) async {
    await tester.enterText(name, 'Aachi 100g');
    await tester.pumpAndSettle();
  }

  Future<void> pickTax(WidgetTester tester) async {
    final field = find.byKey(const Key('product-tax-input'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('VAT (15%)'));
    await tester.pumpAndSettle();
  }

  Future<void> pickCategory(WidgetTester tester) async {
    final field = find.byKey(const Key('product-category-input'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drinks'));
    await tester.pumpAndSettle();
  }

  group('edit success names only what changed and was saved', () {
    for (final (label, steps, title, message)
        in <
          (String, List<Future<void> Function(WidgetTester)>, String, String)
        >[
          (
            'name',
            [rename],
            'Product name updated successfully',
            'New name: Aachi 100g',
          ),
          ('tax', [pickTax], 'Tax updated successfully', 'Tax: VAT (15%)'),
          (
            'category',
            [pickCategory],
            'Category updated successfully',
            'Category: Drinks',
          ),
          (
            'name and tax',
            [rename, pickTax],
            'Product name and tax updated successfully',
            'New name: Aachi 100g · Tax: VAT (15%)',
          ),
          (
            'name and category',
            [pickCategory, rename],
            'Product name and category updated successfully',
            'New name: Aachi 100g · Category: Drinks',
          ),
          (
            'tax and category',
            [pickCategory, pickTax],
            'Tax and category updated successfully',
            'Tax: VAT (15%) · Category: Drinks',
          ),
          (
            'name, tax and category',
            [pickTax, pickCategory, rename],
            'Product name, tax and category updated successfully',
            'New name: Aachi 100g · Tax: VAT (15%) · Category: Drinks',
          ),
        ]) {
      testWidgets(label, (tester) async {
        await mount(tester, edit);
        for (final step in steps) {
          await step(tester);
        }
        await confirmSave(tester, 'Save Changes');
        final success = pendingSuccess(tester)!;
        expect(success.title, title);
        expect(success.message, message);
        expect(find.text('details 0010101010'), findsOneWidget);
        // What was not changed is never announced.
        for (final (field, word) in [
          ('name', 'name'),
          ('tax', 'Tax'),
          ('category', 'Category'),
        ]) {
          final changed = label.contains(field);
          expect(
            '${success.title} ${success.message}'.contains(word),
            changed,
            reason: '$word in "$label"',
          );
        }
      });
    }

    testWidgets('the message follows the selected language', (tester) async {
      await mount(tester, edit, locale: const Locale('nl'));
      await rename(tester);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      final success = pendingSuccess(tester)!;
      expect(success.title, 'Productnaam succesvol bijgewerkt');
      expect(success.message, 'Nieuwe naam: Aachi 100g');
    });
  });

  group('a failed save never announces success or leaves the screen', () {
    final screens =
        <(String, Widget, Future<void> Function(WidgetTester), String)>[
          ('edit', edit, rename, 'Save Changes'),
          (
            'price',
            const ProductPriceUpdatePage(barcode: '0010101010'),
            (tester) async {
              await tester.enterText(
                find.byKey(const Key('new-price-input')),
                '12',
              );
              await tester.pumpAndSettle();
            },
            'Save Changes',
          ),
          (
            'stock',
            const ProductStockUpdatePage(barcode: '0010101010'),
            (tester) async {
              await tester.enterText(
                find.byKey(const Key('stock-count-input')),
                '5',
              );
              await tester.pumpAndSettle();
            },
            'Update Stock',
          ),
        ];
    final failures = <(String, AppFailure, String)>[
      (
        'validation',
        const AppFailure(
          FailureKind.validation,
          'The server rejected this value.',
          code: 'VALIDATION_FAILED',
        ),
        'The server rejected this value.',
      ),
      (
        'permission',
        const AppFailure(
          FailureKind.forbidden,
          'You do not have permission for this operation.',
          code: 'PERMISSION_DENIED',
        ),
        'You do not have permission for this operation.',
      ),
      (
        'version conflict',
        const AppFailure(
          FailureKind.conflict,
          'This product was changed on another device.',
          code: 'VERSION_CONFLICT',
        ),
        'another device',
      ),
      (
        'network',
        const AppFailure(FailureKind.network, 'Offline.'),
        'could not be confirmed',
      ),
    ];
    for (final (screen, page, fill, button) in screens) {
      for (final (kind, failure, shown) in failures) {
        testWidgets('$screen: $kind', (tester) async {
          final repo = FakeDetailsRepository();
          await mount(tester, page, repository: repo);
          await fill(tester);
          repo.writeError = failure;
          await confirmSave(tester, button);
          expect(repo.writes, 1);
          expect(pendingSuccess(tester), isNull);
          expect(find.text('details 0010101010'), findsNothing);
          expect(find.byType(page.runtimeType), findsOneWidget);
          expect(find.textContaining(shown), findsWidgets);
        });
      }
    }
  });

  testWidgets('a rejected edit keeps the draft for a corrected retry', (
    tester,
  ) async {
    final repo = FakeDetailsRepository();
    await mount(tester, edit, repository: repo);
    await rename(tester);
    repo.writeError = const AppFailure(
      FailureKind.validation,
      'The name is not allowed.',
    );
    await confirmSave(tester, 'Save Changes');
    expect(pendingSuccess(tester), isNull);
    repo.writeError = null;
    await confirmSave(tester, 'Save Changes');
    expect(pendingSuccess(tester)?.title, 'Product name updated successfully');
    expect(repo.writes, 2);
  });
}
