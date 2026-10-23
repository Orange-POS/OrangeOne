import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/data/models/product_details_model.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/product_details_fakes.dart';
import '../../support/product_fakes.dart';

void main() {
  test(
    'details routes wait for restoration and reject signed-out sessions',
    () {
      expect(
        authenticationRedirect(const AsyncLoading(), '/home/products/details'),
        '/startup',
      );
      expect(
        authenticationRedirect(const AsyncData(null), '/home/products/details'),
        '/login',
      );
      expect(
        authenticationRedirect(
          AsyncData(testSession),
          '/home/products/details',
        ),
        isNull,
      );
    },
  );

  test(
    'controller denies unauthorized updates and refreshes after writes',
    () async {
      final repo = FakeDetailsRepository()..access = const ProductAccess();
      final container = ProviderContainer.test(
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
      );
      final provider = productDetailsControllerProvider('0010101010');
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      await expectLater(
        container.read(provider.notifier).save(price: '12'),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.writes, 0);
      repo.access = const ProductAccess(updatePrice: true);
      await container.read(provider.notifier).refresh();
      await container.read(provider.notifier).save(price: '12');
      expect(repo.writes, 1);
      expect(repo.loads, 3);
    },
  );
  test('maps stock, optional fields and tax types safely', () {
    final json = productJson()
      ..['taxes'] = [
        {'name': 'Sales', 'amount': 15, 'amount_type': 'percent'},
        {'name': 'Fixed', 'amount': 2, 'amount_type': 'fixed'},
      ];
    final product = ProductDetailsModel.parse(json, '0010101010');
    expect(product.taxes, ['Sales (15%)', 'Fixed']);
    expect(product.stock, 48);
    expect(
      () => ProductDetailsModel.parse({
        ...json,
        'stock_quantity': double.nan,
      }, '0010101010'),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => ProductDetailsModel.parse({
        ...json,
        'barcode': 'other',
      }, '0010101010'),
      throwsA(isA<AppFailure>()),
    );
  });

  test('validates writes before repository invocation', () async {
    final repo = FakeDetailsRepository();
    final useCase = ManageProductDetails(repo);
    expect(() => useCase.rename(10, ' '), throwsFormatException);
    for (final value in ['NaN', 'Infinity', '-1', 'abc']) {
      expect(() => useCase.reprice(10, value), throwsFormatException);
    }
    expect(repo.writes, 0);
    await useCase.reprice(10, '12.50');
    expect(repo.writes, 1);
  });

  Future<void> mount(WidgetTester tester, FakeDetailsRepository repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: ProductDetailsPage(barcode: '0010101010'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('loading, empty and safe error states', (tester) async {
    final repo = FakeDetailsRepository()
      ..pending = Completer<ProductDetailsState>();
    await mount(tester, repo);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.pending!.complete(const ProductDetailsState(null, ProductAccess()));
    await tester.pumpAndSettle();
    expect(find.text('Product not found'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo
      ..pending = null
      ..error = const AppFailure(FailureKind.network, 'Check connection.');
    await mount(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Check connection.'), findsOneWidget);
  });

  testWidgets('details hides discount and preserves disabled permissions', (
    tester,
  ) async {
    final repo = FakeDetailsRepository()..access = const ProductAccess();
    await mount(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text(detailsFixture.name), findsOneWidget);
    expect(find.textContaining('In stock · 48'), findsOneWidget);
    for (final tooltip in [
      'Update price',
      'Edit product name',
      'Add stock (coming soon)',
    ]) {
      final action = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      );
      expect(tester.widget<IconButton>(action).onPressed, isNull);
    }
    expect(find.text('Discount · Mock data'), findsNothing);
    expect(
      find.text('Discount · Mock data', skipOffstage: false),
      findsOneWidget,
    );
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
