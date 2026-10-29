import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/use_cases/create_product.dart';
import 'package:orange_one/features/products/presentation/pages/product_creation_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

import '../../support/product_details_fakes.dart';

void main() {
  late FakeDetailsRepository repository;
  late ProviderContainer container;
  final provider = productCreationControllerProvider('000123');
  setUp(() {
    repository = FakeDetailsRepository()..product = null;
    container = ProviderContainer.test(
      overrides: [
        productDetailsRepositoryProvider.overrideWithValue(repository),
        unsetStockScopeProvider.overrideWithValue('session-a'),
      ],
    );
  });

  Future<ProductCreationState> load() {
    container.listen(provider, (previous, next) {});
    return container.read(provider.future);
  }

  test(
    'validates name, exact CHF precision, barcode, category and explicit taxes',
    () async {
      final value = await load();
      final create = CreateProduct(repository);
      void Function() call({
        String barcode = '000123',
        String name = 'New',
        String price = '2',
        List<int>? taxIds = const [],
        int? categoryId = 4,
        String stock = '',
      }) =>
          () => create.validate(
            barcode: barcode,
            name: name,
            price: price,
            taxIds: taxIds,
            categoryId: categoryId,
            stock: stock,
            context: value.context,
          );
      for (final name in ['', '   ', 'bad\nname']) {
        expect(call(name: name), throwsFormatException);
      }
      for (final price in ['-1', 'NaN', '1.234', 'CHF 2']) {
        expect(call(price: price), throwsFormatException);
      }
      expect(call(barcode: ''), throwsFormatException);
      expect(call(taxIds: null), throwsFormatException);
      expect(call(taxIds: [999]), throwsFormatException);
      expect(call(categoryId: null), throwsFormatException, reason: 'required');
      expect(call(categoryId: 999), throwsFormatException);
      expect(call(stock: '-1'), throwsFormatException);
      final draft = create.validate(
        barcode: '000123',
        name: ' New ',
        price: '2,50',
        taxIds: [],
        categoryId: 4,
        context: value.context,
      );
      expect(draft.barcode, '000123');
      expect(draft.name, 'New');
      expect(draft.price.minorUnits, 250);
      expect(draft.taxIds, isEmpty);
      expect(draft.categoryId, 4);
      expect(draft.initialQuantity, isNull, reason: 'stock stays unset');
    },
  );

  test('price is optional and defaults to 0.00', () async {
    final value = await load();
    final draft = CreateProduct(repository).validate(
      barcode: '000123',
      name: 'New',
      price: '  ',
      taxIds: [],
      categoryId: 4,
      context: value.context,
    );
    expect(draft.price.formatted, '0.00');
  });

  test('stock is optional; an entered 0 is a real quantity', () async {
    final value = await load();
    NewProduct draft(String stock) => CreateProduct(repository).validate(
      barcode: '000123',
      name: 'New',
      price: '1',
      taxIds: [],
      categoryId: 4,
      stock: stock,
      context: value.context,
    );
    expect(draft('').initialQuantity, isNull);
    expect(draft('0').initialQuantity?.text, '0');
    expect(draft('12,5').initialQuantity?.text, '12.5');
  });

  test('the configured default tax is applied without a selection', () async {
    repository
      ..taxes = const [
        ProductTax(id: 1, label: 'VAT'),
        ProductTax(id: 2, label: 'Reduced'),
      ]
      ..defaultTaxIds = [2, 99];
    final value = await load();
    expect(value.taxIds, [2], reason: 'ids that are not offered are ignored');
    final controller = container.read(provider.notifier)
      ..edit(name: 'New', categoryId: 4);
    expect(container.read(provider).value!.canSubmit, isTrue);
    await controller.save();
    expect(repository.submittedProduct!.taxIds, [2]);
    expect(repository.submittedProduct!.price.formatted, '0.00');
  });

  test('without a configured default the tax must be chosen', () async {
    final value = await load();
    expect(value.taxIds, isNull, reason: 'no tax is invented');
    container.read(provider.notifier).edit(name: 'New', categoryId: 4);
    expect(container.read(provider).value!.canSubmit, isFalse);
    container.read(provider.notifier).edit(taxIds: []);
    expect(container.read(provider).value!.canSubmit, isTrue);
  });

  test(
    'name, category and tax are required; price and stock are not',
    () async {
      repository.defaultTaxIds = [1];
      await load();
      final controller = container.read(provider.notifier);
      expect(container.read(provider).value!.canSubmit, isFalse);
      controller.edit(name: 'New');
      expect(
        container.read(provider).value!.canSubmit,
        isFalse,
        reason: 'category is required',
      );
      controller.edit(categoryId: 5);
      expect(container.read(provider).value!.canSubmit, isTrue);
      controller.edit(stock: 'abc');
      expect(container.read(provider).value!.canSubmit, isFalse);
    },
  );

  test('a created category is added to the form and selected', () async {
    await load();
    final controller = container.read(provider.notifier);
    final created = await controller.createCategory('Snacks');
    final value = container.read(provider).value!;
    expect(repository.categoryCreates, 1);
    expect(value.categoryId, created.id);
    expect(value.categoryName, 'Snacks');
    expect(value.context.categories.map((c) => c.name), contains('Snacks'));
  });

  test('category creation respects permission and keeps the form', () async {
    repository.access = const ProductAccess(
      createProduct: true,
      updatePrice: true,
      readReferences: true,
    );
    await load();
    final controller = container.read(provider.notifier)
      ..edit(name: 'Kept', categoryId: 4);
    await expectLater(
      controller.createCategory('Snacks'),
      throwsFormatException,
    );
    expect(repository.categoryCreates, 0);
    repository.access = const ProductAccess(
      createProduct: true,
      updatePrice: true,
      readReferences: true,
      createCategory: true,
    );
    container.invalidate(provider);
    await container.read(provider.future);
    repository.categoryError = const AppFailure(
      FailureKind.conflict,
      'Category exists.',
    );
    container.read(provider.notifier).edit(name: 'Kept', categoryId: 4);
    await expectLater(
      container.read(provider.notifier).createCategory('Spices'),
      throwsA(isA<AppFailure>()),
    );
    expect(container.read(provider).value!.name, 'Kept');
    expect(container.read(provider).value!.categoryId, 4);
  });

  test(
    'blocks duplicate submissions and publishes confirmed creation',
    () async {
      await load();
      final controller = container.read(provider.notifier)
        ..edit(name: 'New', price: '12.50', taxIds: [], categoryId: 4);
      repository.pendingWrite = Completer<ProductDetails>();
      final save = controller.save();
      await controller.save();
      expect(repository.creates, 1);
      expect(container.read(provider).value!.busy, isTrue);
      repository.pendingWrite!.complete(
        const ProductDetails(
          id: 11,
          name: 'New',
          barcode: '000123',
          price: 12.5,
          stock: 0,
        ),
      );
      await save;
      expect(container.read(provider).value!.phase, ProductCreationPhase.saved);
      expect(repository.submittedProduct!.barcode, '000123');
      expect(repository.submittedProduct!.categoryId, 4);
    },
  );

  test('stock left empty is marked not set; an entered stock is not', () async {
    await load();
    container
        .read(provider.notifier)
        .edit(name: 'New', taxIds: [], categoryId: 4);
    await container.read(provider.notifier).save();
    expect(container.read(unsetStockProvider), {11});
    expect(repository.submittedProduct!.initialQuantity, isNull);

    final other = FakeDetailsRepository()..product = null;
    final second = ProviderContainer.test(
      overrides: [
        productDetailsRepositoryProvider.overrideWithValue(other),
        unsetStockScopeProvider.overrideWithValue('session-a'),
      ],
    );
    final secondProvider = productCreationControllerProvider('000123');
    second.listen(secondProvider, (previous, next) {});
    await second.read(secondProvider.future);
    second
        .read(secondProvider.notifier)
        .edit(name: 'New', taxIds: [], categoryId: 4, stock: '0');
    await second.read(secondProvider.notifier).save();
    expect(second.read(unsetStockProvider), isEmpty);
    expect(other.submittedProduct!.initialQuantity?.text, '0');
  });

  test(
    'uncertain and conflict outcomes preserve draft and require checking',
    () async {
      await load();
      final controller = container.read(provider.notifier)
        ..edit(name: 'New', price: '12.50', taxIds: [1], categoryId: 4);
      repository.writeError = const AppFailure(
        FailureKind.conflict,
        'Barcode conflict.',
      );
      await controller.save();
      expect(container.read(provider).value!.name, 'New');
      expect(container.read(provider).value!.price, '12.50');
      expect(container.read(provider).value!.taxIds, [1]);
      expect(container.read(provider).value!.canSubmit, isFalse);
      await controller.save();
      expect(repository.creates, 1);
      await controller.check();
      repository.writeError = const AppFailure(
        FailureKind.backend,
        'Unavailable',
      );
      await controller.save();
      expect(
        container.read(provider).value!.phase,
        ProductCreationPhase.uncertain,
      );
      expect(container.read(provider).value!.name, 'New');
    },
  );

  test('rejected save preserves fields for correction', () async {
    await load();
    final controller = container.read(provider.notifier)
      ..edit(name: 'New', price: '0', taxIds: [], categoryId: 4);
    repository.writeError = const AppFailure(
      FailureKind.validation,
      'Check tax.',
    );
    await controller.save();
    expect(container.read(provider).value!.phase, ProductCreationPhase.editing);
    expect(container.read(provider).value!.name, 'New');
    expect(container.read(provider).value!.message, 'Check tax.');
  });

  late GoRouter router;
  Future<void> mount(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const ProductCreationPage(barcode: '000123'),
        ),
        GoRoute(
          name: 'productDetails',
          path: '/details',
          builder: (context, state) =>
              Text('details ${state.uri.queryParameters['barcode']}'),
        ),
        GoRoute(
          name: 'productScanner',
          path: '/scan',
          builder: (context, state) => const Text('scanner'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: OrangeTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickCategory(WidgetTester tester, String name) async {
    await tester.ensureVisible(
      find.byKey(const Key('create-product-category')),
    );
    await tester.tap(find.byKey(const Key('create-product-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('the form has no name card and shows the cloud, not Powered By', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(ProductNameCard), findsNothing);
    expect(find.textContaining('Powered'), findsNothing);
    expect(find.byTooltip('Edit product name'), findsNothing);
    expect(find.text('Create New Product'), findsOneWidget);
    expect(find.text('000123'), findsOneWidget);
    expect(find.text('Not Set'), findsOneWidget, reason: 'stock hint');
    expect(find.text('Out of stock'), findsNothing);
  });

  testWidgets('default tax is shown; category and the optional fields', (
    tester,
  ) async {
    repository
      ..taxes = const [ProductTax(id: 1, label: '15%')]
      ..defaultTaxIds = [1];
    await mount(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('create-product-tax')),
        matching: find.text('15%'),
      ),
      findsOneWidget,
    );
    expect(find.text('Select Category'), findsOneWidget);
    expect(find.text('Price (optional)'), findsOneWidget);
    expect(find.text('Stock Quantity (optional)'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create Product'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Save asks for confirmation; only Confirm creates', (
    tester,
  ) async {
    repository.defaultTaxIds = [1];
    await mount(tester);
    await tester.enterText(
      find.byKey(const Key('create-product-name')),
      'New product',
    );
    await pickCategory(tester, 'Spices');
    final create = find.widgetWithText(FilledButton, 'Create Product');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Confirm new product'), findsOneWidget);
    expect(find.textContaining('Price: CHF 0.00'), findsOneWidget);
    expect(find.textContaining('Stock: Not Set'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.creates, 0, reason: 'cancel never submits');
    expect(find.text('New product'), findsOneWidget, reason: 'form kept');

    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repository.creates, 1);
    expect(find.text('details 000123'), findsOneWidget);
    final success = container.read(productSuccessProvider)!;
    expect(success.barcode, '000123');
    expect(success.title, 'Product Created Successfully');
    expect(success.message, contains('CHF 0.00'));
    expect(container.read(unsetStockProvider), {11});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed creation stays on the form with its entries', (
    tester,
  ) async {
    repository
      ..defaultTaxIds = [1]
      ..writeError = const AppFailure(FailureKind.validation, 'Check name.');
    await mount(tester);
    await tester.enterText(find.byKey(const Key('create-product-name')), 'Bad');
    await pickCategory(tester, 'Drinks');
    final create = find.widgetWithText(FilledButton, 'Create Product');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Check name.'), findsOneWidget);
    expect(find.text('Bad'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('details 000123'), findsNothing);
    expect(container.read(productSuccessProvider), isNull);
  });

  testWidgets('a category added in the picker is selected and applied', (
    tester,
  ) async {
    await mount(tester);
    await tester.ensureVisible(
      find.byKey(const Key('create-product-category')),
    );
    await tester.tap(find.byKey(const Key('create-product-category')));
    await tester.pumpAndSettle();
    expect(find.text('No Category'), findsNothing, reason: 'required');
    await tester.enterText(
      find.byKey(const Key('category-new-input')),
      'Snacks',
    );
    await tester.tap(find.byKey(const Key('category-add-button')));
    await tester.pumpAndSettle();
    expect(repository.categoryCreates, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('create-product-category')),
        matching: find.text('Snacks'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without category permission the picker has no add row', (
    tester,
  ) async {
    repository.access = const ProductAccess(
      createProduct: true,
      updatePrice: true,
      readReferences: true,
    );
    await mount(tester);
    await tester.ensureVisible(
      find.byKey(const Key('create-product-category')),
    );
    await tester.tap(find.byKey(const Key('create-product-category')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('category-add-button')), findsNothing);
    expect(find.text('Spices'), findsOneWidget);
  });

  testWidgets('a category that cannot be created shows its error', (
    tester,
  ) async {
    repository.categoryError = const AppFailure(
      FailureKind.conflict,
      'Category exists.',
    );
    await mount(tester);
    await tester.ensureVisible(
      find.byKey(const Key('create-product-category')),
    );
    await tester.tap(find.byKey(const Key('create-product-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-new-input')),
      'Spices',
    );
    await tester.tap(find.byKey(const Key('category-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('Category exists.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('create-product-category')),
        matching: find.text('Select Category'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('invalid price and stock show their errors', (tester) async {
    await mount(tester);
    await tester.enterText(find.byKey(const Key('new-price-input')), '1.234');
    await tester.enterText(
      find.byKey(const Key('create-product-stock')),
      'abc',
    );
    await tester.pump();
    expect(find.textContaining('Enter a valid price'), findsOneWidget);
    expect(find.textContaining('non-negative number'), findsOneWidget);
  });

  for (final language in appLanguages) {
    testWidgets('the creation form is in ${language.name}', (tester) async {
      await mount(tester, locale: language.locale);
      final l10n = await AppLocalizations.delegate.load(language.locale);
      for (final text in [
        l10n.createTitle,
        l10n.productNameLabel,
        l10n.productCategoryLabel,
        l10n.categorySelect,
        l10n.createPriceLabel,
        l10n.createStockLabel,
        l10n.stockNotSet,
        l10n.productTaxLabel,
        l10n.createButton,
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading and failed preparation can be retried safely', (
    tester,
  ) async {
    repository.pendingCreation = Completer();
    container.listen(provider, (previous, next) {});
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const ProductCreationPage(barcode: '000123'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: OrangeTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    repository.pendingCreation!.completeError(
      const AppFailure(FailureKind.backend, 'Unable to load creation options.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load creation options.'), findsOneWidget);
    repository.pendingCreation = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-product-name')), findsOneWidget);
    expect(repository.creates, 0);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('fixed creation controls fit $size and keyboard', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('create-product-name')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-product-name')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.text('Create New Product'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Create Product'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('permitted entry saves; missing permissions block it', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const Key('create-product-name')), findsOneWidget);
    final controller = container.read(provider.notifier)
      ..edit(name: 'New', price: '2.00', taxIds: [], categoryId: 4);
    expect(container.read(provider).value!.canSubmit, isTrue);
    await controller.save();
    expect(repository.creates, 1);
    repository
      ..product = null
      ..access = const ProductAccess();
    router.go('/');
    container.invalidate(provider);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create Product'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('do not have permission'), findsOneWidget);
    expect(repository.creates, 1);
  });
}
