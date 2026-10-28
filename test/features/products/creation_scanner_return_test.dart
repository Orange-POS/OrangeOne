import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';
import '../../support/product_fakes.dart';

void main() {
  for (final systemBack in [false, true]) {
    testWidgets(
      'creation replacement returns to fresh scanner, systemBack=$systemBack',
      (tester) async {
        final products = FakeProductRepository()..product = null;
        final details = FakeDetailsRepository()..product = null;
        var cameras = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(
                FakeAuthRepository()..restored = testSession,
              ),
              utcNowProvider.overrideWithValue(() => testNow),
              productRepositoryProvider.overrideWithValue(products),
              productDetailsRepositoryProvider.overrideWithValue(details),
              productCameraBuilderProvider.overrideWithValue((
                context,
                onCode,
                onStatus,
              ) {
                cameras++;
                return FilledButton(
                  onPressed: () => onCode('999000'),
                  child: const Text('Scan test barcode'),
                );
              }),
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
        await tester.tap(find.text('Scan test barcode'));
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
        await tester.tap(find.widgetWithText(FilledButton, 'Create Product'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.text('Created product'), findsOneWidget);
        expect(
          find.text('Scan test barcode', skipOffstage: false),
          findsNothing,
        );
        final beforeReturn = cameras;
        if (systemBack) {
          container.read(routerProvider).pop();
        } else {
          await tester.tap(find.byTooltip('Open Scanner'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Scan test barcode'), findsOneWidget);
        expect(cameras, greaterThan(beforeReturn));
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
        await tester.tap(find.text('Scan test barcode'));
        await tester.pumpAndSettle();
        expect(find.text('Created product'), findsOneWidget);
        expect(products.barcodes, ['999000', '999000']);
        expect(details.creates, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
