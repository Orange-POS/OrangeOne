import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';

void main() {
  test('edit route waits for restoration and rejects signed out sessions', () {
    expect(
      authenticationRedirect(const AsyncLoading(), '/home/products/edit'),
      '/startup',
    );
    expect(
      authenticationRedirect(const AsyncData(null), '/home/products/edit'),
      '/login',
    );
    expect(
      authenticationRedirect(AsyncData(testSession), '/home/products/edit'),
      isNull,
    );
  });
  testWidgets(
    'pencil opens edit; Confirm saves and returns to details with the toast',
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
      await tester.tap(find.byTooltip('Edit product name'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductEditPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('product-name-input')),
        'Aachi 100g',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0, reason: 'a confirmation comes first');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      // Success returns to Product Details with the success toast above the
      // Open Scanner button.
      expect(find.byType(ProductEditPage), findsNothing);
      expect(find.text('Aachi 100g'), findsWidgets);
      final toast = find.byKey(const Key('product-success-toast'));
      expect(toast, findsOneWidget);
      expect(find.text('Product name updated successfully'), findsOneWidget);
      expect(
        tester.getBottomLeft(toast).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('open-scanner-button'))).dy,
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(toast, findsNothing);
      await container.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();
      container
          .read(routerProvider)
          .goNamed('productEdit', queryParameters: {'barcode': '0010101010'});
      await tester.pumpAndSettle();
      expect(find.text('Tap to scan QR'), findsOneWidget);
      expect(find.byType(ProductEditPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
