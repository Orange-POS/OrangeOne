import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/product_details_fakes.dart';

class _Catalog implements ProductRepository {
  final products = <String, Product>{};
  final requested = <String>[];
  Completer<void>? hold;

  @override
  Future<Product?> findByBarcode(String barcode, {bool refresh = false}) async {
    requested.add(barcode);
    if (hold != null) await hold!.future;
    return products[barcode];
  }
}

Product _product(
  int id, {
  double price = 10,
  double? stock = 48,
  String reference = 'REF-HIDDEN',
  String? category,
}) => Product(
  id: id,
  name: 'Product $id',
  barcode: 'BC-$id',
  price: price,
  stockQuantity: stock,
  unit: 'Units',
  reference: reference,
  category: category,
);

void main() {
  late _Catalog catalog;
  late MemorySecretStore store;
  var scanCode = 'BC-1';
  setUp(() {
    catalog = _Catalog();
    for (var id = 1; id <= 7; id++) {
      catalog.products['BC-$id'] = _product(id, price: id * 10.0);
    }
    store = MemorySecretStore();
    scanCode = 'BC-1';
  });

  Future<ProviderContainer> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..restored = testSession,
        ),
        utcNowProvider.overrideWithValue(() => testNow),
        secretStoreProvider.overrideWithValue(store),
        productRepositoryProvider.overrideWithValue(catalog),
        productDetailsRepositoryProvider.overrideWithValue(
          FakeDetailsRepository(),
        ),
        productCameraBuilderProvider.overrideWithValue(
          (context, onCode, onStatus) => FilledButton(
            onPressed: () => onCode(scanCode),
            child: const Text('Test scan'),
          ),
        ),
      ],
      child: const App(),
    );
    await tester.pumpWidget(scope);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(App)));
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('scan-product-button')));
    await tester.pumpAndSettle();
  }

  /// Scans [barcode], then returns from its details to the scanner.
  Future<void> scan(WidgetTester tester, String barcode) async {
    scanCode = barcode;
    await tester.tap(find.text('Test scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-scanner-button')));
    await tester.pumpAndSettle();
  }

  Finder recent(String barcode) => find.byKey(Key('recent-$barcode'));

  testWidgets('the card starts with its hint and no history', (tester) async {
    await mount(tester);
    await openScanner(tester);
    expect(find.text('Last scanned'), findsOneWidget);
    expect(find.text('Scan a product barcode to look it up.'), findsOneWidget);
    expect(recent('BC-1'), findsNothing);
  });

  testWidgets('one card shows the latest scan and each scan replaces it', (
    tester,
  ) async {
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    expect(recent('BC-1'), findsOneWidget);
    await scan(tester, 'BC-2');
    expect(find.text('Scan a product barcode to look it up.'), findsNothing);
    expect(recent('BC-1'), findsNothing, reason: 'replaced, not stacked');
    expect(recent('BC-2'), findsOneWidget);
    expect(find.byKey(const Key('recent-category-badge')), findsOneWidget);
    expect(find.textContaining('REF-HIDDEN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the card shows category and barcode badges, stock and CHF price',
    (tester) async {
      catalog.products['BC-2'] = _product(2, price: 20, category: 'Spices');
      await mount(tester);
      await openScanner(tester);
      await scan(tester, 'BC-2');
      final card = recent('BC-2');
      for (final text in [
        'Product 2',
        'Spices',
        'BC-2',
        'In stock · 48 Units',
        'CHF 20.00',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      final category = tester.getRect(
        find.byKey(const Key('recent-category-badge')),
      );
      final barcode = tester.getRect(
        find.byKey(const Key('recent-barcode-badge')),
      );
      final stock = tester.getRect(find.text('In stock · 48 Units'));
      final price = tester.getRect(find.text('CHF 20.00'));
      // Barcode takes the stock badge's place (the badge row), stock the old
      // barcode place (under it); the category badge comes first.
      expect(category.left, lessThan(barcode.left));
      expect(stock.top, greaterThan(barcode.bottom - 1));
      expect(
        price.right,
        greaterThan(stock.right),
        reason: 'price on the right',
      );
      expect(price.right, closeTo(tester.getRect(card).right - 8 - 4, 12));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a product without a category shows "No Category"', (
    tester,
  ) async {
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    expect(
      find.descendant(
        of: find.byKey(const Key('recent-category-badge')),
        matching: find.text('No Category'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('stock states are shown on the cards', (tester) async {
    catalog.products['BC-1'] = _product(1, stock: null);
    catalog.products['BC-2'] = _product(2, stock: 0);
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    expect(
      find.descendant(
        of: recent('BC-1'),
        matching: find.text('Stock unavailable'),
      ),
      findsOneWidget,
    );
    await scan(tester, 'BC-2');
    expect(
      find.descendant(
        of: recent('BC-2'),
        matching: find.text('Out of stock · 0 Units'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a rescanned product replaces the card without a duplicate', (
    tester,
  ) async {
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    await scan(tester, 'BC-2');
    await scan(tester, 'BC-1');
    expect(recent('BC-1'), findsOneWidget);
    expect(recent('BC-2'), findsNothing);
  });

  testWidgets('only the latest of many scans is displayed', (tester) async {
    await mount(tester);
    await openScanner(tester);
    for (var id = 1; id <= 7; id++) {
      await scan(tester, 'BC-$id');
    }
    expect(recent('BC-7'), findsOneWidget);
    expect(find.byKey(const Key('recent-category-badge')), findsOneWidget);
    for (var id = 1; id <= 6; id++) {
      expect(recent('BC-$id'), findsNothing);
    }
  });

  testWidgets('unknown barcodes are not added to the history', (tester) async {
    await mount(tester);
    await openScanner(tester);
    scanCode = 'UNKNOWN';
    await tester.tap(find.text('Test scan'));
    await tester.pumpAndSettle();
    expect(find.text('Create New Product'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a product barcode to look it up.'), findsOneWidget);
  });

  testWidgets('tapping a recent product looks it up and opens its details', (
    tester,
  ) async {
    final container = await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    await scan(tester, 'BC-2');
    catalog.requested.clear();
    await tester.tap(recent('BC-2'));
    await tester.pumpAndSettle();
    expect(catalog.requested, ['BC-2'], reason: 'the existing lookup is used');
    expect(
      container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .last
          .matchedLocation,
      '/home/products/details',
    );
    expect(find.byTooltip('Open Scanner'), findsOneWidget);
    // Back on the scanner, the tapped product is still the displayed card.
    await tester.tap(find.byTooltip('Open Scanner'));
    await tester.pumpAndSettle();
    expect(recent('BC-2'), findsOneWidget);
  });

  testWidgets('a recent product that vanished offers to add it', (
    tester,
  ) async {
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    catalog.products.remove('BC-1');
    await tester.tap(recent('BC-1'));
    await tester.pumpAndSettle();
    expect(find.text('Create New Product'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent products are announced as buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    expect(
      find.bySemanticsLabel(RegExp('Open product Product 1, barcode BC-1')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('while a lookup runs the card shows its progress', (
    tester,
  ) async {
    await mount(tester);
    await openScanner(tester);
    await scan(tester, 'BC-1');
    expect(recent('BC-1'), findsOneWidget);
    catalog.hold = Completer<void>();
    scanCode = 'BC-2';
    await tester.tap(find.text('Test scan'));
    await tester.pump();
    expect(find.text('Looking up product…'), findsWidgets);
    expect(recent('BC-1'), findsNothing);
    catalog.hold!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Scanner'));
    await tester.pumpAndSettle();
    expect(recent('BC-2'), findsOneWidget);
    expect(recent('BC-1'), findsNothing);
  });

  testWidgets('Home has no "Powered By" line; the scanner never had one', (
    tester,
  ) async {
    await mount(tester);
    expect(find.textContaining('Powered By'), findsNothing);
    expect(find.text('Tap to scan Barcode'), findsOneWidget);
    await openScanner(tester);
    expect(find.textContaining('Powered By'), findsNothing);
  });

  for (final language in appLanguages) {
    final code = language.locale.languageCode;
    testWidgets('Home and scanner are in ${language.name}', (tester) async {
      store.values[localeStorageKey] = code;
      await mount(tester);
      final l10n = await AppLocalizations.delegate.load(language.locale);
      expect(find.text(l10n.homeScanTitle), findsOneWidget);
      expect(find.text(l10n.homeScanSubtitle), findsOneWidget);
      expect(find.byTooltip(l10n.homeLogoutTooltip), findsOneWidget);
      await openScanner(tester);
      expect(find.text(l10n.scannerTitle), findsOneWidget);
      expect(find.byTooltip(l10n.scannerBackTooltip), findsOneWidget);
      expect(find.text(l10n.recentTitle), findsOneWidget);
      expect(find.text(l10n.recentEmpty), findsOneWidget);
      expect(find.text(l10n.scanOpeningCamera), findsOneWidget);
      await scan(tester, 'BC-1');
      expect(find.text(l10n.recentTitle), findsOneWidget);
      expect(
        find.descendant(
          of: recent('BC-1'),
          matching: find.text('${l10n.stockInStock} · 48 Units'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('recent-category-badge')),
          matching: find.text(l10n.categoryNone),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lookup errors and unknown products are translated', (
    tester,
  ) async {
    store.values[localeStorageKey] = 'fr';
    await mount(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
    await openScanner(tester);
    // The camera builder is replaced: an invalid code gives the safe error.
    scanCode = '\u0001';
    await tester.tap(find.text('Test scan'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.scanAnother), findsOneWidget);
    expect(find.text(l10n.recentTitle), findsOneWidget);
  });

  testWidgets('the layout holds on a small phone with enlarged text', (
    tester,
  ) async {
    catalog.products['BC-5'] = _product(
      5,
      price: 1234.5,
      category: 'Herbs, spices and seasonings',
    );
    await mount(tester);
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openScanner(tester);
    await scan(tester, 'BC-5');
    expect(recent('BC-5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
