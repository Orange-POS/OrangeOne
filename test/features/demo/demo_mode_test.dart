import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/features/demo/domain/entities/demo_sample.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/providers/recent_scans_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/wifi_fakes.dart';

const _water = '2000000000011';
const _yogurt = '2000000000073';

ProviderContainer _container({FakeAuthRepository? auth}) =>
    ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
        productRepositoryOverride,
        productDetailsRepositoryOverride,
        recentScansRepositoryOverride,
        unsetStockScopeOverride,
      ],
    );

/// A provider read that fails because there is no signed-in session.
final Matcher _signedOut = throwsA(
  predicate<Object>((error) => error.toString().contains('unauthenticated')),
);

void main() {
  group('normal mode is unchanged', () {
    test('Demo Mode is off and the real repositories need a session', () async {
      final container = _container();
      expect(container.read(demoModeProvider), isNull);
      // Without a session nothing is served: the demo never fills the gap.
      expect(() => container.read(productRepositoryProvider), _signedOut);
      expect(
        () => container.read(productDetailsRepositoryProvider),
        _signedOut,
      );
    });

    test('the redirect only treats Demo Mode as signed in when asked', () {
      expect(authenticationRedirect(const AsyncData(null), '/home'), '/login');
      expect(
        authenticationRedirect(const AsyncData(null), '/home', demo: true),
        isNull,
      );
      expect(
        authenticationRedirect(const AsyncData(null), '/login', demo: true),
        '/home',
      );
      expect(authenticationRedirect(const AsyncData(null), '/login'), isNull);
    });
  });

  group('demo repositories', () {
    late ProviderContainer container;

    setUp(() {
      container = _container();
      container.read(demoModeProvider.notifier).enable();
      container.read(demoLoginProvider.notifier).signIn(DemoSample.manager);
    });

    test('look up, search and filter the sample products', () async {
      final product = await container
          .read(productRepositoryProvider)
          .findByBarcode(_water);
      expect(product?.name, 'Sparkling Water 1L');
      expect(product?.category, 'Beverages');
      expect(
        await container.read(productRepositoryProvider).findByBarcode('1'),
        isNull,
      );

      final details = container.read(productDetailsRepositoryProvider);
      final found = await details.searchProducts(query: 'milk');
      expect(found.items.map((item) => item.name), ['Whole Milk 1L']);
      final dairy = await details.searchProducts(categoryId: 3);
      expect(dairy.items, hasLength(3));
      final page = await details.searchProducts(limit: 5);
      expect(page.items, hasLength(5));
      expect(page.nextCursor, '5');
      final last = await details.searchProducts(limit: 5, cursor: '10');
      expect(last.items, hasLength(2));
      expect(last.nextCursor, isNull);
    });

    test('price updates are guarded by the product version', () async {
      final repository = container.read(productDetailsRepositoryProvider);
      final product = (await repository.load(_water)).product!;
      final updated = await repository.updatePrice(
        product,
        ChfPrice.parse('1.50'),
      );
      expect(updated.price, 1.5);
      expect((await repository.load(_water)).product?.price, 1.5);
      // The old version is stale now, like a backend `VERSION_CONFLICT`.
      await expectLater(
        repository.updatePrice(product, ChfPrice.parse('9.99')),
        throwsA(
          isA<AppFailure>().having((f) => f.code, 'code', 'VERSION_CONFLICT'),
        ),
      );
    });

    test('update, add and remove change the stock', () async {
      final repository = container.read(productDetailsRepositoryProvider);
      var product = (await repository.load(_water)).product!;
      var result = await repository.adjustStock(
        product,
        StockCount.parse('100'),
      );
      expect((result.previousQuantity, result.newQuantity), (120, 100));
      product = result.product;
      result = await repository.adjustStock(
        product,
        StockCount.parse('40'),
        operation: StockOperation.add,
      );
      expect(result.newQuantity, 140);
      product = result.product;
      result = await repository.adjustStock(
        product,
        StockCount.parse('15'),
        operation: StockOperation.remove,
      );
      expect(result.newQuantity, 125);
      await expectLater(
        repository.adjustStock(
          result.product,
          StockCount.parse('500'),
          operation: StockOperation.remove,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect((await repository.load(_water)).product?.stock, 125);
    });

    test('products and categories can be created and edited', () async {
      final repository = container.read(productDetailsRepositoryProvider);
      final context = await repository.prepareCreation('4000');
      expect(context.canCreate, isTrue);
      expect(context.initialTaxIds, [1]);
      final category = await repository.createCategory('Frozen');
      final created = await repository.createProduct(
        NewProduct(
          barcode: '4000',
          name: 'Frozen Peas',
          price: ChfPrice.parse('2.10'),
          taxIds: const [2],
          categoryId: category.id,
        ),
      );
      expect(created.category?.name, 'Frozen');
      expect(created.stock, isNull);
      await expectLater(
        repository.createProduct(
          NewProduct(
            barcode: '4000',
            name: 'Again',
            price: ChfPrice.parse('1'),
            taxIds: const [],
          ),
        ),
        throwsA(isA<AppFailure>()),
      );
      final renamed = await repository.updateInformation(
        created,
        name: 'Garden Peas',
        category: const CategoryChange(null),
      );
      expect(renamed.name, 'Garden Peas');
      expect(renamed.category, isNull);
      expect(
        (await container.read(productRepositoryProvider).findByBarcode('4000'))
            ?.name,
        'Garden Peas',
      );
    });

    test('an untracked product cannot be counted', () async {
      final repository = container.read(productDetailsRepositoryProvider);
      final bag = (await repository.load('2000000000127')).product!;
      expect(bag.stock, isNull);
      await expectLater(
        repository.adjustStock(bag, StockCount.parse('5')),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('read-only sample', () {
    test('cannot change anything the manager can', () async {
      final container = _container();
      container.read(demoModeProvider.notifier).enable();
      container.read(demoLoginProvider.notifier).signIn(DemoSample.viewer);
      final state = await container
          .read(productDetailsRepositoryProvider)
          .load(_water);
      expect(state.product?.name, 'Sparkling Water 1L');
      expect(state.access.editName, isFalse);
      expect(state.access.updatePrice, isFalse);
      expect(state.access.adjustStock, isFalse);
      expect(state.access.createProduct, isFalse);
    });
  });

  group('isolation and lifecycle', () {
    test('Demo Mode never starts by itself and never touches a session', () {
      final auth = FakeAuthRepository();
      final container = _container(auth: auth);
      expect(container.read(routerProvider), isNotNull);
      expect(container.read(demoModeProvider), isNull);
      container.read(demoModeProvider.notifier).enable();
      // Switching it on opens no session; only a sample QR code does.
      expect(container.read(demoLoginProvider), isNull);
      expect(container.read(unsetStockScopeProvider), isNull);
      container.read(demoLoginProvider.notifier).signIn(DemoSample.manager);
      expect(container.read(demoLoginProvider)?.scope, startsWith('demo|'));
      expect(auth.signIns + auth.tokenRequests + auth.signOuts, 0);
      expect(container.read(activeSessionProvider), isNull);
      expect(container.read(readCacheIdentityProvider), isNull);
    });

    test('signing in needs Demo Mode to be on', () {
      final container = _container();
      container.read(demoLoginProvider.notifier).signIn(DemoSample.manager);
      expect(container.read(demoLoginProvider), isNull);
    });

    test(
      'logout and disabling discard every change and the next run is clean',
      () async {
        final container = _container();
        final mode = container.read(demoModeProvider.notifier)..enable();
        final login = container.read(demoLoginProvider.notifier)
          ..signIn(DemoSample.manager);
        final first = container.read(demoLoginProvider)!;
        var repository = container.read(productDetailsRepositoryProvider);
        final product = (await repository.load(_water)).product!;
        await repository.updatePrice(product, ChfPrice.parse('7.77'));
        container
            .read(productSuccessProvider.notifier)
            .show(barcode: _water, title: 'Saved', message: 'Saved');
        expect(container.read(unsetStockScopeProvider), first.scope);

        login.signOut();
        expect(container.read(demoModeProvider), isNotNull);
        expect(container.read(productSuccessProvider), isNull);
        expect(container.read(unsetStockScopeProvider), isNull);
        expect(
          () => container.read(productDetailsRepositoryProvider),
          _signedOut,
        );

        login.signIn(DemoSample.manager);
        final second = container.read(demoLoginProvider)!;
        expect(second.scope, isNot(first.scope));
        repository = container.read(productDetailsRepositoryProvider);
        expect((await repository.load(_water)).product?.price, 1.2);

        mode.disable();
        expect(container.read(demoModeProvider), isNull);
        expect(container.read(demoLoginProvider), isNull);
      },
    );

    test('demo scans and the last-scanned history stay in memory', () async {
      final container = _container();
      container.read(demoModeProvider.notifier).enable();
      container.read(demoLoginProvider.notifier).signIn(DemoSample.manager);
      final scans = container.read(recentScansControllerProvider.notifier);
      await container.read(recentScansControllerProvider.future);
      final product = await container
          .read(productRepositoryProvider)
          .findByBarcode(_yogurt);
      await scans.record(product!);
      expect(
        (await container.read(recentScansControllerProvider.future))
            .single
            .name,
        'Greek Yogurt 150g',
      );
      container.read(demoLoginProvider.notifier).signOut();
      container.read(demoLoginProvider.notifier).signIn(DemoSample.manager);
      expect(
        await container.read(recentScansControllerProvider.future),
        isEmpty,
      );
    });
  });

  group('screens', () {
    Future<(ProviderContainer, FakeAuthRepository)> open(
      WidgetTester tester, {
      FakeAuthRepository? auth,
    }) async {
      final fake = auth ?? FakeAuthRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fake),
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
            wifiOverride(Stream.value(true)),
            qrCameraBuilderProvider.overrideWithValue(
              (context, onCode, onStatus) =>
                  const SizedBox(key: Key('real-camera')),
            ),
            productCameraBuilderProvider.overrideWithValue(
              (context, onCode, onStatus) => const SizedBox(),
            ),
            productRepositoryOverride,
            productDetailsRepositoryOverride,
            recentScansRepositoryOverride,
            unsetStockScopeOverride,
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      return (
        ProviderScope.containerOf(tester.element(find.byType(App))),
        fake,
      );
    }

    Future<void> turnOnFromSettings(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('demo-mode-switch')));
      await tester.pumpAndSettle();
    }

    Future<void> openSampleLogin(WidgetTester tester, String sample) async {
      await turnOnFromSettings(tester);
      await tester.tap(find.byKey(const Key('scan-login-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('demo-sample-$sample')));
      await tester.pumpAndSettle();
    }

    testWidgets('Settings turn Demo Mode on and off in any flavor', (
      tester,
    ) async {
      final (container, auth) = await open(tester);
      expect(find.byKey(const Key('demo-banner')), findsNothing);

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('demo-mode-switch'));
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      // The crash tools exist in development only (this build is not).
      expect(find.byKey(const Key('trigger-crash-button')), findsNothing);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(container.read(demoModeProvider), isNotNull);
      // Turning it on does not sign in: the QR login screen is next.
      expect(container.read(demoLoginProvider), isNull);
      expect(find.byKey(const Key('scan-login-button')), findsOneWidget);
      expect(find.byKey(const Key('demo-banner')), findsOneWidget);
      expect(find.text('Demo Mode · sample data only'), findsOneWidget);

      await tester.tap(find.byKey(const Key('demo-banner-settings')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(container.read(demoModeProvider), isNull);
      expect(find.byKey(const Key('scan-login-button')), findsOneWidget);
      expect(find.byKey(const Key('demo-banner')), findsNothing);
      expect(auth.signIns + auth.tokenRequests, 0);
    });

    testWidgets('the QR login offers sample QR codes only in Demo Mode', (
      tester,
    ) async {
      final (container, _) = await open(tester);
      await tester.tap(find.byKey(const Key('scan-login-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('real-camera')), findsOneWidget);
      expect(find.byKey(const Key('demo-sample-qr-list')), findsNothing);
      container.read(routerProvider).goNamed('login');
      await tester.pumpAndSettle();

      await turnOnFromSettings(tester);
      await tester.tap(find.byKey(const Key('scan-login-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('demo-sample-qr-list')), findsOneWidget);
      expect(find.byKey(const Key('demo-sample-manager')), findsOneWidget);
      expect(find.byKey(const Key('demo-sample-viewer')), findsOneWidget);
      expect(find.byKey(const Key('real-camera')), findsNothing);
    });

    testWidgets('a sample QR code signs in; scan, change price, logout', (
      tester,
    ) async {
      final (container, auth) = await open(tester);
      await openSampleLogin(tester, 'manager');
      expect(container.read(demoLoginProvider)?.sample, DemoSample.manager);
      expect(find.byKey(const Key('logout-button')), findsOneWidget);
      expect(find.byKey(const Key('demo-banner')), findsOneWidget);

      // Sample barcodes replace the camera in the scanner.
      unawaited(
        container.read(routerProvider).pushNamed<bool>('productScanner'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('demo-barcode-$_water')));
      await tester.pumpAndSettle();
      expect(find.text('Sparkling Water 1L'), findsWidgets);

      final repository = container.read(productDetailsRepositoryProvider);
      final product = (await repository.load(_water)).product!;
      await repository.updatePrice(product, ChfPrice.parse('2.00'));
      expect((await repository.load(_water)).product?.price, 2);

      container.read(routerProvider).goNamed('home');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      // Logging out leaves the sample session but Demo Mode stays on.
      expect(container.read(demoLoginProvider), isNull);
      expect(container.read(demoModeProvider), isNotNull);
      expect(find.byKey(const Key('scan-login-button')), findsOneWidget);
      expect(auth.signIns + auth.tokenRequests + auth.signOuts, 0);
    });

    testWidgets('the read-only sample signs in with restricted access', (
      tester,
    ) async {
      final (container, _) = await open(tester);
      await openSampleLogin(tester, 'viewer');
      expect(container.read(demoLoginProvider)?.sample, DemoSample.viewer);
      container
          .read(routerProvider)
          .goNamed('productDetails', queryParameters: {'barcode': _water});
      await tester.pumpAndSettle();
      expect(find.text('Sparkling Water 1L'), findsWidgets);
    });

    testWidgets('a real session blocks the switch and stays signed in', (
      tester,
    ) async {
      final auth = FakeAuthRepository()..restored = testSession;
      final (container, _) = await open(tester, auth: auth);
      unawaited(container.read(routerProvider).pushNamed('settings'));
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('demo-mode-switch')),
      );
      expect(tile.onChanged, isNull);
      expect(container.read(demoModeProvider), isNull);
      expect(container.read(activeSessionProvider), testSession);
    });

    testWidgets('a restart starts in normal mode with the real QR login', (
      tester,
    ) async {
      var (container, _) = await open(tester);
      await turnOnFromSettings(tester);
      expect(container.read(demoModeProvider), isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      (container, _) = await open(tester);
      expect(container.read(demoModeProvider), isNull);
      await tester.tap(find.byKey(const Key('scan-login-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('demo-sample-qr-list')), findsNothing);
    });
  });
}
