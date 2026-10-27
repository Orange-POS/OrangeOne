import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/edit_product_information.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';

import '../../support/product_details_fakes.dart';

void main() {
  late FakeDetailsRepository repo;
  late ProviderContainer container;
  final provider = productEditControllerProvider('0010101010');
  setUp(() {
    repo = FakeDetailsRepository();
    container = ProviderContainer.test(
      overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
    )..listen(provider, (_, _) {});
  });
  ProductEditController controller() => container.read(provider.notifier);
  ProductEditState value() => container.read(provider).requireValue;

  test('prefills and validates permitted fields before writes', () async {
    await container.read(provider.future);
    expect(value().name, detailsFixture.name);
    expect(value().canSubmit, isFalse);
    controller().changeName(' ');
    expect(value().nameError, 'Product name is required.');
    await controller().save();
    expect(repo.writes, 0);
    controller().changeName(' New product ');
    await controller().save();
    expect(value().phase, ProductEditPhase.saved);
    expect(repo.product?.name, 'New product');
    expect(repo.writtenTaxIds, isNull);
  });
  test('explicit no-tax clears taxes while dismissal preserves them', () async {
    await container.read(provider.future);
    controller().selectTax(null);
    expect(value().selectedTaxIds, isEmpty);
    await controller().save();
    expect(repo.writtenTaxIds, isEmpty);
    expect(value().details.product?.taxes, isEmpty);
  });
  test('selects only offered tax identities', () async {
    await container.read(provider.future);
    controller().selectTax(999);
    expect(value().selectedTaxIds, isNull);
    controller().selectTax(1);
    await controller().save();
    expect(repo.writtenTaxIds, [1]);
    expect(repo.product?.taxes, ['VAT (15%)']);
  });
  test('single-flight save and no state changes while busy', () async {
    repo.pendingWrite = Completer<ProductDetails>();
    await container.read(provider.future);
    controller().changeName('Changed');
    final operation = controller().save();
    await Future<void>.delayed(Duration.zero);
    await controller().save();
    controller().changeName('Ignored');
    expect(repo.writes, 1);
    expect(value().name, 'Changed');
    repo.pendingWrite!.complete(
      ProductDetails(
        id: detailsFixture.id,
        name: 'Changed',
        barcode: detailsFixture.barcode,
        price: detailsFixture.price,
        stock: detailsFixture.stock,
      ),
    );
    await operation;
    expect(value().phase, ProductEditPhase.saved);
  });
  test('permission loss blocks saving after preflight', () async {
    await container.read(provider.future);
    controller().changeName('Changed');
    repo.access = const ProductAccess();
    await controller().save();
    expect(repo.writes, 0);
    expect(value().canSubmit, isFalse);
  });
  test(
    'reference failure keeps name editing and preserves existing tax',
    () async {
      repo.referencesError = invalidResponse;
      container.invalidate(provider);
      await container.read(provider.future);
      expect(value().canSelectTax, isFalse);
      controller().changeName('Changed');
      await controller().save();
      expect(repo.writtenTaxIds, isNull);
      expect(repo.writes, 1);
    },
  );
  test('uncertain write blocks retry until a safe server read', () async {
    await container.read(provider.future);
    controller().changeName('Changed');
    repo.writeError = const AppFailure(
      FailureKind.timeout,
      'Connection timed out.',
    );
    await controller().save();
    expect(value().phase, ProductEditPhase.uncertain);
    await controller().save();
    expect(repo.writes, 1);
    repo.writeError = null;
    await controller().refresh();
    expect(value().phase, ProductEditPhase.editing);
    expect(value().name, 'Changed');
    expect(repo.writes, 1);
  });
  test('changed server name requires review before another save', () async {
    await container.read(provider.future);
    controller().changeName('My draft');
    repo.product = const ProductDetails(
      id: 10,
      name: 'Server name',
      barcode: '0010101010',
      price: 100,
      stock: 48,
    );
    await controller().save();
    expect(repo.writes, 0);
    expect(value().name, 'My draft');
    expect(value().details.product?.name, 'Server name');
  });
  test('rejects disallowed taxes and names in the domain', () {
    final useCase = EditProductInformation(repo);
    expect(
      () => EditProductInformation.validateName('a\nname'),
      throwsFormatException,
    );
    expect(
      () => EditProductInformation.validateName('a' * 201),
      throwsFormatException,
    );
    expect(
      () => useCase(detailsFixture, 'Name', taxIds: [9]),
      throwsFormatException,
    );
    expect(repo.writes, 0);
  });
  test('disposing during preflight never writes', () async {
    await container.read(provider.future);
    controller().changeName('Changed');
    repo.pending = Completer<ProductDetailsState>();
    final operation = controller().save();
    container.dispose();
    repo.pending!.complete(ProductDetailsState(detailsFixture, repo.access));
    await operation;
    expect(repo.writes, 0);
  });

  test('a category change sends only the category with the version', () async {
    await container.read(provider.future);
    expect(value().categoryLabel, 'Spices');
    expect(value().canSelectCategory, isTrue);
    controller().selectCategory(4);
    expect(value().canSubmit, isFalse, reason: 'unchanged category');
    controller().selectCategory(5);
    expect(value().categoryLabel, 'Drinks');
    await controller().save();
    expect(value().phase, ProductEditPhase.saved);
    expect(repo.writtenCategory?.id, 5);
    expect(repo.writtenName, isNull);
    expect(repo.writtenTaxIds, isNull);
    expect(repo.writtenVersions, ['3']);
    expect(value().details.product?.category?.name, 'Drinks');
  });

  test('No category removes it; unknown categories are ignored', () async {
    await container.read(provider.future);
    controller().selectCategory(99);
    expect(value().selectedCategory, isNull);
    controller().selectCategory(null);
    expect(value().categoryLabel, 'No category');
    await controller().save();
    expect(repo.writtenCategory, isNotNull);
    expect(repo.writtenCategory!.id, isNull);
  });

  test('category editing follows its own permission', () async {
    repo.access = const ProductAccess(
      editName: true,
      readReferences: true,
      updateTaxes: true,
    );
    container.invalidate(provider);
    await container.read(provider.future);
    expect(value().canSelectCategory, isFalse);
    controller().selectCategory(5);
    expect(value().selectedCategory, isNull);
    expect(value().canSelectTax, isTrue);
  });

  test('a stale version reloads details and keeps the draft', () async {
    await container.read(provider.future);
    controller().changeName('My draft');
    repo.writeError = const AppFailure(
      FailureKind.conflict,
      'This product was changed on another device.',
      code: 'VERSION_CONFLICT',
    );
    final loads = repo.loads;
    await controller().save();
    expect(repo.writes, 1);
    expect(repo.loads, greaterThan(loads + 1));
    expect(value().phase, ProductEditPhase.editing);
    expect(value().name, 'My draft');
    expect(value().message, contains('another device'));
    // Nothing is retried automatically; the user saves again explicitly.
    repo.writeError = null;
    await controller().save();
    expect(repo.writes, 2);
    expect(value().phase, ProductEditPhase.saved);
  });
}
