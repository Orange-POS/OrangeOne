import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/widgets/info_badge.dart';

import '../../support/product_details_fakes.dart';

void main() {
  var opened = 0;
  setUp(() => opened = 0);

  Future<void> mount(
    WidgetTester tester,
    FakeDetailsRepository repo, {
    Locale locale = const Locale('en'),
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const ProductDetailsPage(barcode: '0010101010'),
        ),
        GoRoute(
          name: 'productScanner',
          path: '/scan',
          builder: (context, state) {
            opened++;
            return const Text('scanner');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the category badge sits left of the stock badge', (
    tester,
  ) async {
    // The test font is far wider than a real one; leave room for one row.
    await mount(tester, FakeDetailsRepository(), width: 900);
    final category = find.byKey(const Key('product-category-badge'));
    expect(
      find.descendant(of: category, matching: find.text('Spices')),
      findsOneWidget,
    );
    final badges = find.byType(InfoBadge);
    expect(badges, findsNWidgets(2));
    final categoryBox = tester.getRect(badges.first);
    final stockBox = tester.getRect(badges.last);
    expect(
      find.descendant(
        of: badges.last,
        matching: find.text('In stock · 48 Units'),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(category), categoryBox);
    expect(categoryBox.right, lessThanOrEqualTo(stockBox.left));
    expect(categoryBox.height, stockBox.height, reason: 'same design');
  });

  testWidgets('a product without a category shows "No Category"', (
    tester,
  ) async {
    final repo = FakeDetailsRepository()
      ..product = const ProductDetails(
        id: 11,
        name: 'Plain',
        barcode: '0010101010',
        price: 5,
        stock: 1,
        unit: 'Units',
        currency: 'CHF',
        version: '1',
      );
    await mount(tester, repo);
    expect(
      find.descendant(
        of: find.byKey(const Key('product-category-badge')),
        matching: find.text('No Category'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no back arrow and no "Powered by"; Open Scanner navigates', (
    tester,
  ) async {
    await mount(tester, FakeDetailsRepository());
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('Back to scanner'), findsNothing);
    expect(find.textContaining('Powered'), findsNothing);
    expect(find.byTooltip('Open Scanner'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-scanner-button')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('scanner'), findsOneWidget);
  });

  for (final language in appLanguages) {
    testWidgets('details are fully translated to ${language.name}', (
      tester,
    ) async {
      await mount(tester, FakeDetailsRepository(), locale: language.locale);
      final l10n = await AppLocalizations.delegate.load(language.locale);
      for (final text in [
        l10n.detailsTitle,
        l10n.detailsBarcode,
        l10n.detailsPrice,
        l10n.detailsTax,
        '${l10n.stockInStock} · 48 Units',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      for (final tooltip in [
        l10n.detailsOpenScanner,
        l10n.detailsEditName,
        l10n.detailsUpdatePrice,
        l10n.detailsUpdateStock,
      ]) {
        expect(find.byTooltip(tooltip), findsWidgets, reason: tooltip);
      }
      expect(find.textContaining('Powered'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
