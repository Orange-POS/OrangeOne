import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/scan_dock_bar.dart';

import '../../support/product_details_fakes.dart';

const _tax = Key('product-tax-row');
const _barcode = Key('product-hero-barcode');
const _category = Key('product-category-badge');

void main() {
  /// Product Details with tall content under the price (as a long discount
  /// list), so the page can scroll far enough to fold the card.
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(414, 896),
    double textScale = 1,
    EdgeInsets padding = const EdgeInsets.only(top: 48, bottom: 34),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..padding = FakeViewPadding(top: padding.top, bottom: padding.bottom);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ProductDetailsPage(
            barcode: '0010101010',
            discountsBuilder: (details) =>
                const SizedBox(key: Key('tall-content'), height: 1600),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(
            FakeDetailsRepository(),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder scrollView() => find.byType(CustomScrollView);

  /// Scrolls by [dy] in small steps, checking every frame for layout errors.
  Future<void> scrollBy(WidgetTester tester, double dy) async {
    // A fixed point in the middle of the visible content.
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    final gesture = await tester.startGesture(
      Offset(view.width / 2, view.height * .7),
    );
    final steps = (dy.abs() / 20).ceil();
    for (var step = 0; step < steps; step++) {
      await gesture.moveBy(Offset(0, -dy.sign * 20));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'frame $step');
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the full card first: tax and barcode shown', (tester) async {
    await mount(tester);
    expect(find.byKey(_tax), findsOneWidget);
    expect(find.byKey(_barcode), findsOneWidget);
    expect(find.text('Aachi Fish Fry Masala'), findsOneWidget);
    expect(find.byKey(_category), findsOneWidget);
  });

  testWidgets('scrolling up folds the card; it stays pinned at the top', (
    tester,
  ) async {
    await mount(tester);
    final categoryTop = tester.getTopLeft(find.byKey(_category)).dy;
    final cardBottom = tester.getBottomLeft(find.byKey(_barcode)).dy;
    // Half-way the rows fade and shrink, without jumps or overflow.
    await scrollBy(tester, 60);
    final fading = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(_tax), matching: find.byType(Opacity)),
    );
    expect(fading.opacity, inExclusiveRange(0, 1));
    await scrollBy(tester, 600);
    // Collapsed: no Tax or Barcode, but name, category and stock stay.
    expect(find.byKey(_tax), findsNothing);
    expect(find.byKey(_barcode), findsNothing);
    expect(find.text('Aachi Fish Fry Masala'), findsOneWidget);
    expect(find.textContaining('In stock'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(_category)).dy, categoryTop);
    // The compact card is shorter; the content scrolls under it.
    final stockBottom = tester
        .getBottomLeft(find.textContaining('In stock'))
        .dy;
    expect(stockBottom, lessThan(cardBottom));
    expect(
      tester.getTopLeft(find.byKey(const Key('tall-content'))).dy,
      lessThan(stockBottom + 40),
    );
  });

  testWidgets('scrolling back down expands the card again', (tester) async {
    await mount(tester);
    final barcodeTop = tester.getTopLeft(find.byKey(_barcode)).dy;
    await scrollBy(tester, 600);
    expect(find.byKey(_barcode), findsNothing);
    await scrollBy(tester, -900);
    expect(find.byKey(_tax), findsOneWidget);
    expect(find.byKey(_barcode), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(_barcode)).dy, barcodeTop);
  });

  testWidgets('on a short screen with large text the card scrolls away', (
    tester,
  ) async {
    await mount(
      tester,
      size: const Size(320, 568),
      textScale: 1.6,
      padding: const EdgeInsets.only(top: 20),
    );
    final top = tester.getTopLeft(find.byKey(_category)).dy;
    await tester.drag(scrollView(), const Offset(0, -400));
    await tester.pumpAndSettle();
    // Not pinned: the whole card left with the content.
    expect(
      find.byKey(_category).hitTestable(),
      findsNothing,
      reason: 'the card scrolled off instead of covering the content',
    );
    expect(top, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('white backs the lower page against overscroll', (tester) async {
    await mount(tester);
    final backing = find.byWidgetPredicate(
      (widget) =>
          widget is Positioned &&
          widget.bottom == 0 &&
          widget.child is ColoredBox &&
          (widget.child as ColoredBox).color == Colors.white,
    );
    expect(backing, findsOneWidget);
    // It starts below the panel's rounded corners (below the card).
    expect(
      tester.getTopLeft(backing).dy,
      greaterThan(tester.getBottomLeft(find.byKey(_barcode)).dy),
    );
  });

  group('scan dock', () {
    test('is compact and counts the home indicator as the bar', () {
      // iPhone 11: 34 px home indicator inset (120 px before).
      expect(ScanDockBar.heightFor(34), 94);
      // No inset (Android button navigation): the minimum bar.
      expect(ScanDockBar.heightFor(0), 64);
    });

    testWidgets('keeps the floating scanner button above the safe area', (
      tester,
    ) async {
      await mount(tester);
      final dock = tester.getRect(find.byType(ScanDockBar));
      expect(dock.height, ScanDockBar.heightFor(34));
      expect(dock.bottom, 896);
      final button = tester.getRect(
        find.byKey(const Key('open-scanner-button')),
      );
      expect(button.width, ScanDockBar.buttonSize);
      expect(button.bottom, lessThanOrEqualTo(896 - 34));
      expect(
        find.byKey(const Key('open-scanner-button')).hitTestable(),
        findsOneWidget,
      );
    });
  });
}
