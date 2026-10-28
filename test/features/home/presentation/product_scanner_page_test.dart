import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/product_details_fakes.dart';
import '../../../support/product_fakes.dart';

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester,
    FakeProductRepository products, {
    bool authenticated = true,
  }) async {
    final auth = FakeAuthRepository()
      ..restored = authenticated ? testSession : null;
    final scope = ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        utcNowProvider.overrideWithValue(() => testNow),
        productRepositoryProvider.overrideWithValue(products),
        productDetailsRepositoryProvider.overrideWithValue(
          FakeDetailsRepository()
            ..product = products.product == null ? null : detailsFixture,
        ),
        productCameraBuilderProvider.overrideWithValue(
          (context, onCode, onStatus) => FilledButton(
            onPressed: () {
              onCode('0010101010');
              onCode('0010101010');
            },
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

  testWidgets(
    'home opens protected scanner; found result and explicit rescan',
    (tester) async {
      final products = FakeProductRepository();
      final container = await mount(tester, products);
      await tester.tap(find.text('Tap to scan Barcode'));
      await tester.pumpAndSettle();
      expect(find.text('Scan Barcode'), findsOneWidget);
      expect(
        find.text('Scan a product barcode to look it up.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Test scan'));
      await tester.pumpAndSettle();
      expect(find.text(fixtureProduct.name), findsOneWidget);
      expect(find.text('CHF 100.00'), findsOneWidget);
      expect(products.barcodes.length, 1);
      expect(find.byTooltip('Product information'), findsNothing);
      expect(find.text('Test scan'), findsNothing);
      await tester.tap(find.byTooltip('Open Scanner'));
      await tester.pumpAndSettle();
      expect(products.barcodes.length, 1);
      await tester.tap(find.byTooltip('Back to home'));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/home',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'not found opens a prefilled creation form without any mutation',
    (tester) async {
      final products = FakeProductRepository()..product = null;
      await mount(tester, products);
      await tester.tap(find.text('Tap to scan Barcode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test scan'));
      await tester.pumpAndSettle();
      expect(find.text('0010101010'), findsOneWidget);
      expect(find.text('Product Name'), findsOneWidget);
      expect(find.text('Create New Product'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('create-product-name')),
        'New product',
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Test scan'), findsOneWidget);
      expect(products.barcodes.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading suppresses scans; cancellation ignores late results', (
    tester,
  ) async {
    final products = FakeProductRepository()..pending = Completer<Product?>();
    final container = await mount(tester, products);
    await tester.tap(find.text('Tap to scan Barcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test scan'));
    await tester.pump();
    expect(find.text('Looking up product…'), findsWidgets);
    expect(find.text('Test scan'), findsNothing);
    await tester.tap(find.byTooltip('Back to home'));
    await tester.pumpAndSettle();
    products.pending!.complete(fixtureProduct);
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/home',
    );
    expect(find.text(fixtureProduct.name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network errors offer safe read retry', (tester) async {
    final products = FakeProductRepository()
      ..failure = const AppFailure(
        FailureKind.network,
        'Check your connection.',
      );
    await mount(tester, products);
    await tester.tap(find.text('Tap to scan Barcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test scan'));
    await tester.pumpAndSettle();
    expect(find.text('Check your connection.'), findsOneWidget);
    products.failure = null;
    await tester.tap(find.text('Retry lookup'));
    await tester.pumpAndSettle();
    expect(find.text(fixtureProduct.name), findsOneWidget);
    expect(products.barcodes.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep links and back cannot bypass logout guards', (
    tester,
  ) async {
    final container = await mount(
      tester,
      FakeProductRepository(),
      authenticated: false,
    );
    final router = container.read(routerProvider);
    for (final path in [
      '/home/scan',
      '/home/products/new?barcode=0010101010',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
    }
    await container.read(sessionControllerProvider.notifier).signIn('fixture');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to scan Barcode'));
    await tester.pumpAndSettle();
    await container.read(sessionControllerProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    router.go('/home/scan');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('scanner states fit $size with enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() {
        unawaited(tester.binding.setSurfaceSize(null));
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await mount(tester, FakeProductRepository());
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tap to scan Barcode'));
      await tester.tap(find.text('Tap to scan Barcode'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Test scan'));
      await tester.tap(find.text('Test scan'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
