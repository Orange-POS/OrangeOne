import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/presentation/pages/splash_page.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../test/support/auth_fakes.dart';
import '../test/support/product_details_fakes.dart';
import '../test/support/product_fakes.dart';
import '../test/support/wifi_fakes.dart';

class StartupAuthRepository extends FakeAuthRepository {
  final startup = Completer<AuthSession?>();
  bool firstRestore = true;
  @override
  Future<AuthSession?> restore() async {
    if (firstRestore) {
      firstRestore = false;
      return await startup.future;
    }
    return await super.restore();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const flavor = String.fromEnvironment(
    'TEST_FLAVOR',
    defaultValue: 'development',
  );
  testWidgets('$flavor application starts', (tester) async {
    expect(appFlavor, flavor, reason: 'Native and Dart flavors must match.');
    // The tests expect English text whatever the phone's language is.
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final environment = AppEnvironment.values.byName(flavor)
      ..validateNativeFlavor(appFlavor);
    final repository = StartupAuthRepository();
    final products = FakeProductRepository();
    final details = FakeDetailsRepository();
    var scanBarcode = '0010101010';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentProvider.overrideWithValue(environment),
          authRepositoryProvider.overrideWithValue(repository),
          utcNowProvider.overrideWithValue(() => testNow),
          productRepositoryProvider.overrideWithValue(products),
          productDetailsRepositoryProvider.overrideWithValue(details),
          productCameraBuilderProvider.overrideWithValue(
            (context, onCode, onStatus) => FilledButton(
              onPressed: () => onCode(scanBarcode),
              child: const Text('Test product scan'),
            ),
          ),
          qrCameraBuilderProvider.overrideWithValue(
            (context, onCode, onStatus) => FilledButton(
              onPressed: () => onCode('fixture QR'),
              child: const Text('Test QR scan'),
            ),
          ),
          // The QR scanner is only enabled on Wi-Fi.
          wifiConnected,
          // Isolate the run from the phone's saved language.
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
        ],
        child: const App(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.text('Scan. Sell. Go.'), findsOneWidget);
    repository.startup.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-login-button')));
    await tester.pumpAndSettle();
    expect(find.text('Scan QR Code'), findsOneWidget);
    await tester.tap(find.text('Test QR scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan Barcode'), findsOneWidget);
    await tester.tap(find.text('Tap to scan Barcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test product scan'));
    await tester.pumpAndSettle();
    expect(find.text(fixtureProduct.name), findsOneWidget);
    // The redesigned details screen opens the price page from the pencil.
    await tester.ensureVisible(find.byTooltip('Update price'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Update price'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-price-input')), '125.25');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update Price'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm update'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Price Updated Successfully'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('CHF 125.25'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit product name'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('product-name-input')),
      'Aachi Fish Fry Masala 100g',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Name & Tax Updated Successfully'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Aachi Fish Fry Masala 100g'), findsOneWidget);
    await tester.tap(find.byTooltip('Open Scanner'));
    await tester.pumpAndSettle();
    products.product = null;
    scanBarcode = '999000';
    await tester.tap(find.text('Test product scan'));
    await tester.pumpAndSettle();
    expect(find.text('Create New Product'), findsOneWidget);
    expect(find.text('999000'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('create-product-name')),
      'New mobile product',
    );
    await tester.enterText(find.byKey(const Key('new-price-input')), '12.50');
    await tester.tap(find.byKey(const Key('create-product-tax')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No Tax'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Product'));
    await tester.pumpAndSettle();
    expect(find.text('New Product Created'), findsOneWidget);
    expect(details.creates, 1);
    expect(details.submittedProduct?.barcode, '999000');
    expect(details.submittedProduct?.taxIds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('New mobile product'), findsOneWidget);
    expect(find.text('CHF 12.50'), findsOneWidget);
    await tester.tap(find.byTooltip('Open Scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to home'));
    await tester.pumpAndSettle();

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(repository.signIns, 1);
    expect(tester.takeException(), isNull);
  });
}
