import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/products/data/models/product_details_model.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/product_tax_label.dart';
import 'package:orange_one/features/products/presentation/providers/price_update_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';

import '../../support/product_details_fakes.dart';
import '../../support/product_fakes.dart';

const code = '0010101010';
ProductDetails product({
  String name = 'Original',
  double price = 100,
  List<int>? ids = const [1],
}) => ProductDetails(
  id: 10,
  name: name,
  barcode: code,
  price: price,
  stock: 48,
  taxIds: ids,
  taxes: ids == null || ids.isEmpty ? [] : ['VAT'],
);

void main() {
  late FakeDetailsRepository repo;
  late ProviderContainer container;
  final edit = productEditControllerProvider(code);
  final price = priceUpdateControllerProvider(code);
  setUp(() {
    repo = FakeDetailsRepository()..product = product();
    container =
        ProviderContainer.test(
            overrides: [
              productDetailsRepositoryProvider.overrideWithValue(repo),
            ],
          )
          ..listen(edit, (_, _) {})
          ..listen(price, (_, _) {});
  });

  test(
    'old price response is uncertain, preserves draft and never retries',
    () async {
      await container.read(price.future);
      repo.pendingWrite = Completer<ProductDetails>()..complete(product());
      final controller = container.read(price.notifier)..changePrice('125,25');
      await controller.save(controller.confirmation()!);
      expect(
        container.read(price).requireValue.phase,
        PriceUpdatePhase.uncertain,
      );
      expect(container.read(price).requireValue.draft, '125,25');
      expect(controller.confirmation(), isNull);
      expect(repo.writes, 1);
      repo.pendingWrite = null;
      await controller.refresh();
      expect(container.read(price).requireValue.draft, '125,25');
      await controller.save(controller.confirmation()!);
      expect(container.read(price).requireValue.phase, PriceUpdatePhase.saved);
      expect(repo.writes, 2);
    },
  );

  for (final scenario in ['name', 'tax', 'unknown tax']) {
    test('unconfirmed $scenario response never reports edit success', () async {
      await container.read(edit.future);
      final controller = container.read(edit.notifier)..changeName('Draft');
      if (scenario != 'name') controller.selectTax(null);
      repo.pendingWrite = Completer<ProductDetails>()
        ..complete(
          product(
            name: scenario == 'name' ? 'Original' : 'Draft',
            ids: scenario == 'unknown tax' ? null : [1],
          ),
        );
      await controller.save();
      final result = container.read(edit).requireValue;
      expect(result.phase, ProductEditPhase.uncertain);
      expect(result.name, 'Draft');
      if (scenario != 'name') expect(result.selectedTaxIds, isEmpty);
      expect(result.canSubmit, isFalse);
      await controller.save();
      expect(repo.writes, 1);
    });
  }

  for (final taxOnly in [false, true]) {
    test('conflict preserves explicit No Tax, taxOnly=$taxOnly', () async {
      await container.read(edit.future);
      final controller = container.read(edit.notifier);
      if (!taxOnly) controller.changeName('Draft');
      controller.selectTax(null);
      repo.product = product(name: 'Server changed');
      await controller.save();
      expect(repo.writes, 0);
      expect(container.read(edit).requireValue.selectedTaxIds, isEmpty);
      expect(
        container.read(edit).requireValue.name,
        taxOnly ? 'Original' : 'Draft',
      );
      await controller.save();
      expect(repo.writtenTaxIds, isEmpty);
      expect(container.read(edit).requireValue.phase, ProductEditPhase.saved);
    });
  }

  test(
    'permission loss preserves tax intent until authorized refresh',
    () async {
      await container.read(edit.future);
      final controller = container.read(edit.notifier)..selectTax(null);
      repo.access = const ProductAccess();
      await controller.save();
      expect(container.read(edit).requireValue.selectedTaxIds, isEmpty);
      expect(container.read(edit).requireValue.canSubmit, isFalse);
      expect(repo.writes, 0);
      repo.access = const ProductAccess(
        editName: true,
        readReferences: true,
        updateTaxes: true,
      );
      await controller.refresh();
      await controller.save();
      expect(repo.writtenTaxIds, isEmpty);
      expect(container.read(edit).requireValue.phase, ProductEditPhase.saved);
    },
  );

  for (final conflict in [false, true]) {
    test(
      'removed tax remains visible and blocked, conflict=$conflict',
      () async {
        repo.product = product(ids: []);
        container.invalidate(edit);
        await container.read(edit.future);
        final controller = container.read(edit.notifier)..selectTax(1);
        repo.taxes = [];
        if (conflict) repo.product = product(name: 'Server changed', ids: []);
        await controller.save();
        final result = container.read(edit).requireValue;
        expect(repo.writes, 0);
        expect(result.selectedTaxIds, [1]);
        expect(result.taxLabel, 'Selected tax unavailable');
        expect(result.taxSelectionError, isNotNull);
        expect(result.canSubmit, isFalse);
        expect(result.canSelectTax, isTrue);
        controller
          ..selectTax(null)
          ..changeName('Reviewed draft');
        await controller.save();
        expect(container.read(edit).requireValue.phase, ProductEditPhase.saved);
        // No Tax already matches the fresh backend: this is a name-only edit.
        expect(repo.writtenTaxIds, isNull);
        expect(
          container.read(edit).requireValue.details.product!.taxIds,
          isEmpty,
        );
      },
    );
  }

  test(
    'reference failure preserves selected identity and blocks saving',
    () async {
      repo.product = product(ids: []);
      container.invalidate(edit);
      await container.read(edit.future);
      final controller = container.read(edit.notifier)..selectTax(1);
      repo
        ..product = product(name: 'Changed', ids: [])
        ..referencesError = Exception('synthetic reference failure');
      await controller.save();
      expect(container.read(edit).requireValue.selectedTaxIds, [1]);
      expect(container.read(edit).requireValue.canSubmit, isFalse);
      expect(repo.writes, 0);
    },
  );

  final cases = <String, Object?>{
    'omitted': null,
    'null': null,
    'false': false,
    'empty': <Object?>[],
    'populated': [
      {'id': 1, 'name': 'VAT', 'amount': 15, 'amount_type': 'percent'},
    ],
  };
  for (final entry in cases.entries) {
    final json = productJson();
    if (entry.key == 'omitted') {
      json.remove('taxes');
    } else {
      json['taxes'] = entry.value;
    }
    final expected = entry.key == 'empty'
        ? 'No taxes assigned'
        : entry.key == 'populated'
        ? 'VAT (15%)'
        : 'Tax information unavailable';
    test('mapper distinguishes ${entry.key} tax information', () {
      final mapped = ProductDetailsModel.parse(json, code);
      expect(mapped.currentTaxLabel, expected);
      expect(
        mapped.taxIds,
        entry.key == 'empty'
            ? isEmpty
            : entry.key == 'populated'
            ? [1]
            : isNull,
      );
    });
    for (final editing in [false, true]) {
      testWidgets('tax label ${entry.key}, edit=$editing', (tester) async {
        final repository = FakeDetailsRepository()
          ..product = ProductDetailsModel.parse(json, code)
          ..taxes = const [ProductTax(id: 1, label: 'VAT (15%)')];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productDetailsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              home: editing
                  ? const ProductEditPage(barcode: code)
                  : const ProductDetailsPage(barcode: code),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected), findsWidgets);
        if (entry.key != 'empty') {
          expect(find.text('No taxes assigned'), findsNothing);
        }
      });
    }
  }
}
