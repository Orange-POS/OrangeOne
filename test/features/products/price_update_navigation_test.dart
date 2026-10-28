import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';

void main() {
  test('price route is guarded during restore and after logout', () {
    expect(
      authenticationRedirect(const AsyncLoading(), '/home/products/price'),
      '/startup',
    );
    expect(
      authenticationRedirect(const AsyncData(null), '/home/products/price'),
      '/login',
    );
    expect(
      authenticationRedirect(AsyncData(testSession), '/home/products/price'),
      isNull,
    );
  });

  testWidgets(
    'details opens the price page; Confirm returns to details with the toast',
    (tester) async {
      final repo = FakeDetailsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository()..restored = testSession,
            ),
            utcNowProvider.overrideWithValue(() => testNow),
            productDetailsRepositoryProvider.overrideWithValue(repo),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(App)),
      );
      container
          .read(routerProvider)
          .goNamed(
            'productDetails',
            queryParameters: {'barcode': '0010101010'},
          );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Update price'));
      await tester.tap(find.byTooltip('Update price'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductPriceUpdatePage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('new-price-input')),
        '125.25',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      // No Done step: success returns to details with the toast.
      expect(find.byKey(const Key('product-success-toast')), findsOneWidget);
      expect(find.text('Price Updated Successfully'), findsOneWidget);
      expect(find.text('New price: CHF 125.25'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const Key('product-success-toast')), findsNothing);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/home/products/details',
      );
      expect(find.text('CHF 125.25'), findsOneWidget);
      expect(find.byType(ProductPriceUpdatePage), findsNothing);
      await container.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();
      container
          .read(routerProvider)
          .goNamed('productPrice', queryParameters: {'barcode': '0010101010'});
      await tester.pumpAndSettle();
      expect(find.text('Tap to scan QR'), findsOneWidget);
      expect(find.byKey(const Key('new-price-input')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
