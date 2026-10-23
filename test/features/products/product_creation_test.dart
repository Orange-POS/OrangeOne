import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/create_product.dart';
import 'package:orange_one/features/products/presentation/pages/product_creation_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
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
      ],
    );
  });

  Future<ProductCreationState> load() {
    container.listen(provider, (previous, next) {});
    return container.read(provider.future);
  }

  test(
    'validates name, exact CHF precision, barcode and explicit taxes',
    () async {
      final value = await load();
      final create = CreateProduct(repository);
      for (final name in ['', '   ', 'bad\nname']) {
        expect(
          () => create.validate(
            barcode: '000123',
            name: name,
            price: '2.00',
            taxIds: [],
            context: value.context,
          ),
          throwsFormatException,
        );
      }
      for (final price in ['', '-1', 'NaN', '1.234', 'CHF 2']) {
        expect(
          () => create.validate(
            barcode: '000123',
            name: 'New',
            price: price,
            taxIds: [],
            context: value.context,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => create.validate(
          barcode: '',
          name: 'New',
          price: '2',
          taxIds: [],
          context: value.context,
        ),
        throwsFormatException,
      );
      expect(
        () => create.validate(
          barcode: '000123',
          name: 'New',
          price: '2',
          taxIds: null,
          context: value.context,
        ),
        throwsFormatException,
      );
      expect(
        () => create.validate(
          barcode: '000123',
          name: 'New',
          price: '2',
          taxIds: [999],
          context: value.context,
        ),
        throwsFormatException,
      );
      final draft = create.validate(
        barcode: '000123',
        name: ' New ',
        price: '2,50',
        taxIds: [],
        context: value.context,
      );
      expect(draft.barcode, '000123');
      expect(draft.name, 'New');
      expect(draft.price.minorUnits, 250);
      expect(draft.taxIds, isEmpty);
    },
  );

  test(
    'blocks duplicate submissions and publishes confirmed creation',
    () async {
      await load();
      final controller = container.read(provider.notifier)
        ..edit(name: 'New', price: '12.50', taxIds: []);
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
    },
  );

  test(
    'uncertain and conflict outcomes preserve draft and require checking',
    () async {
      await load();
      final controller = container.read(provider.notifier)
        ..edit(name: 'New', price: '12.50', taxIds: [1]);
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
      ..edit(name: 'New', price: '0', taxIds: []);
    repository.writeError = const AppFailure(
      FailureKind.validation,
      'Check tax.',
    );
    await controller.save();
    expect(container.read(provider).value!.phase, ProductCreationPhase.editing);
    expect(container.read(provider).value!.name, 'New');
    expect(container.read(provider).value!.message, 'Check tax.');
  });

  testWidgets('prefilled form validates, selects tax and displays success', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: OrangeTheme.light,
          home: const ProductCreationPage(barcode: '000123'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('000123'), findsOneWidget);
    expect(find.text('Stock unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create Product'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('create-product-name')),
      'New product',
    );
    await tester.enterText(find.byKey(const Key('new-price-input')), '1.234');
    await tester.pump();
    expect(find.textContaining('Enter a valid price'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('new-price-input')), '12.50');
    await tester.ensureVisible(find.byKey(const Key('create-product-tax')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-product-tax')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No Tax'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Product'));
    await tester.pumpAndSettle();
    expect(find.text('New Product Created'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('Out of stock · 0 Units'), findsOneWidget);
    expect(repository.creates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and failed preparation can be retried safely', (
    tester,
  ) async {
    repository.pendingCreation = Completer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: OrangeTheme.light,
          home: const ProductCreationPage(barcode: '000123'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: OrangeTheme.light,
            home: const ProductCreationPage(barcode: '000123'),
          ),
        ),
      );
      await tester.pumpAndSettle();
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

  testWidgets(
    'original backend permits entry but missing permissions block it',
    (tester) async {
      repository.supportsCreateOnly = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: OrangeTheme.light,
            home: const ProductCreationPage(barcode: '000123'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-product-name')), findsOneWidget);
      final controller = container.read(provider.notifier)
        ..edit(name: 'New', price: '2.00', taxIds: []);
      expect(container.read(provider).value!.canSubmit, isTrue);
      await controller.save();
      expect(repository.creates, 1);
      repository
        ..product = null
        ..access = const ProductAccess();
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
    },
  );
}
