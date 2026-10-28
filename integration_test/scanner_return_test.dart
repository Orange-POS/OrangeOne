import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../test/support/auth_fakes.dart';
import '../test/support/product_details_fakes.dart';
import '../test/support/product_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final systemBack in [false]) {
    testWidgets(
      'creation replacement returns to fresh scanner, systemBack=$systemBack',
      (tester) async {
        final products = FakeProductRepository()..product = null;
        final details = FakeDetailsRepository()..product = null;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(
                FakeAuthRepository()..restored = testSession,
              ),
              utcNowProvider.overrideWithValue(() => testNow),
              productRepositoryProvider.overrideWithValue(products),
              productDetailsRepositoryProvider.overrideWithValue(details),
            ],
            child: const App(),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(App)),
        );
        await tester.tap(find.text('Tap to scan Barcode'));
        await tester.pumpAndSettle();
        final camera = await runningCamera(tester);
        camera.onDetect!(
          const BarcodeCapture(
            barcodes: [
              Barcode(rawValue: '999000', format: BarcodeFormat.ean13),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('create-product-name')),
          'Created product',
        );
        await tester.enterText(
          find.byKey(const Key('new-price-input')),
          '12.50',
        );
        await tester.ensureVisible(find.byKey(const Key('create-product-tax')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('create-product-tax')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('No Tax'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('create-product-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Spices'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Create Product'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(find.text('Created product'), findsOneWidget);
        expect(find.byType(MobileScanner, skipOffstage: false), findsNothing);

        if (systemBack) {
          container.read(routerProvider).pop();
        } else {
          await tester.tap(find.byTooltip('Open Scanner'));
        }
        await tester.pumpAndSettle();
        final restarted = await runningCamera(tester);
        expect(restarted.controller, isNot(same(camera.controller)));
        expect(container.read(productLookupControllerProvider).value, isNull);
        expect(find.text('Product not found'), findsNothing);
        expect(find.text('Add product'), findsNothing);
        products.product = const Product(
          id: 11,
          name: 'Created product',
          barcode: '999000',
          price: 12.5,
          stockQuantity: 0,
          unit: 'Units',
        );

        restarted.onDetect!(
          const BarcodeCapture(
            barcodes: [
              Barcode(rawValue: '999000', format: BarcodeFormat.ean13),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Created product'), findsOneWidget);
        expect(products.barcodes, ['999000', '999000']);
        expect(details.creates, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<MobileScanner> runningCamera(WidgetTester tester) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump();
    final finder = find.byType(MobileScanner);
    if (finder.evaluate().isNotEmpty) {
      final camera = tester.widget<MobileScanner>(finder);
      if (camera.controller?.value.isRunning ?? false) return camera;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('Hardware camera did not start within 15 seconds');
}
