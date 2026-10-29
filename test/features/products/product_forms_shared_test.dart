import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_stock_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_success_toast.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';

import '../../support/product_details_fakes.dart';
import '../../support/product_router.dart';

class _Unset extends UnsetStockController {
  @override
  Set<int> build() => const {10};
}

const _noStock = ProductDetails(
  id: 10,
  name: 'Fresh product',
  barcode: '0010101010',
  price: 5,
  stock: 0,
  unit: 'Units',
  currency: 'CHF',
  version: '1',
  stockAdjustable: true,
  stockLocationId: 8,
  quantityDecimals: 2,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget page,
    FakeDetailsRepository repo, {
    Locale locale = const Locale('en'),
    List<Override> more = const [],
  }) async {
    await tester.pumpWidget(
      productFormApp(
        page,
        locale: locale,
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(repo),
          ...more,
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in appLanguages) {
    testWidgets('edit, price and stock screens are in ${language.name}', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(language.locale);
      final screens = <(Widget, List<String>)>[
        (
          const ProductEditPage(barcode: '0010101010'),
          [
            l10n.editTitle,
            l10n.productNameLabel,
            l10n.productTaxLabel,
            l10n.productCategoryLabel,
            l10n.commonSaveChanges,
            l10n.detailsBarcode,
          ],
        ),
        (
          const ProductPriceUpdatePage(barcode: '0010101010'),
          [
            l10n.priceTitle,
            l10n.priceNewLabel,
            l10n.priceCurrentLabel,
            l10n.commonSaveChanges,
          ],
        ),
        (
          const ProductStockUpdatePage(barcode: '0010101010'),
          [
            l10n.stockTitle,
            l10n.stockCountedLabel,
            l10n.stockCurrentLabel,
            l10n.stockActionUpdate,
            l10n.stockOperationUpdate,
            l10n.stockOperationAdd,
            l10n.stockOperationRemove,
          ],
        ),
      ];
      for (final (page, texts) in screens) {
        await mount(
          tester,
          page,
          FakeDetailsRepository(),
          locale: language.locale,
        );
        for (final text in texts) {
          expect(find.text(text), findsWidgets, reason: text);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('the price confirmation popup is translated', (tester) async {
    const locale = Locale('nl');
    final l10n = await AppLocalizations.delegate.load(locale);
    await mount(
      tester,
      const ProductPriceUpdatePage(barcode: '0010101010'),
      FakeDetailsRepository(),
      locale: locale,
    );
    await tester.enterText(find.byKey(const Key('new-price-input')), '12');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonSaveChanges));
    await tester.pumpAndSettle();
    expect(find.text(l10n.priceConfirmTitle), findsOneWidget);
    expect(find.text(l10n.commonCancel), findsOneWidget);
    expect(find.text(l10n.commonConfirm), findsOneWidget);
  });

  testWidgets('stock created without a quantity is Not Set, not zero', (
    tester,
  ) async {
    final repo = FakeDetailsRepository()..product = _noStock;
    await mount(
      tester,
      const ProductStockUpdatePage(barcode: '0010101010'),
      repo,
      more: [unsetStockProvider.overrideWith(_Unset.new)],
    );
    expect(find.text('Not Set'), findsWidgets);
    expect(find.textContaining('Out of stock'), findsNothing);
  });

  testWidgets('a counted zero is Out of stock, never Not Set', (tester) async {
    final repo = FakeDetailsRepository()..product = _noStock;
    await mount(
      tester,
      const ProductStockUpdatePage(barcode: '0010101010'),
      repo,
    );
    expect(find.textContaining('Out of stock · 0 Units'), findsWidgets);
    expect(find.text('Not Set'), findsNothing);
  });

  testWidgets('the success toast shows for its product and then fades', (
    tester,
  ) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const Column(
                children: [
                  ProductSuccessToast(
                    barcode: '1',
                    duration: Duration(milliseconds: 300),
                  ),
                  ProductSuccessToast(
                    barcode: '2',
                    duration: Duration(milliseconds: 300),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('product-success-toast')), findsNothing);
    ref
        .read(productSuccessProvider.notifier)
        .show(barcode: '1', title: 'Saved', message: 'Details here');
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget, reason: 'only barcode 1');
    expect(find.text('Details here'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsNothing);
    expect(ref.read(productSuccessProvider), isNull);
  });
}
