import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';

import '../../../../support/product_details_fakes.dart';

class MockProductDetailsRepository extends Mock
    implements ProductDetailsRepository;

ProductDetails _withId(int id) => ProductDetails(
  id: id,
  name: detailsFixture.name,
  barcode: detailsFixture.barcode,
  price: detailsFixture.price,
  stock: detailsFixture.stock,
  version: detailsFixture.version,
);

void main() {
  setUpAll(() => registerFallbackValue(ChfPrice.parse('0')));
  late MockProductDetailsRepository repository;
  late ManageProductDetails manage;

  setUp(() {
    repository = MockProductDetailsRepository();
    manage = ManageProductDetails(repository);
  });

  test(
    'load normalizes whitespace and preserves barcode leading zeros',
    () async {
      const state = ProductDetailsState(detailsFixture, ProductAccess());
      when(() => repository.load('0010101010')).thenAnswer((_) async => state);

      expect(await manage.load(' 0010101010 '), same(state));

      verify(() => repository.load('0010101010')).called(1);
      verifyNoMoreInteractions(repository);
    },
  );

  test('invalid barcode never reaches the repository', () {
    for (final barcode in [
      '',
      '  ',
      '12\u0000',
      List.filled(257, '1').join(),
    ]) {
      expect(() => manage.load(barcode), throwsFormatException);
    }
    verifyZeroInteractions(repository);
  });

  test('rename trims names before writing', () async {
    when(() => repository.updateName(detailsFixture, 'Updated product'))
        .thenAnswer((_) async => detailsFixture);

    await manage.rename(detailsFixture, ' Updated product ');

    verify(() => repository.updateName(detailsFixture, 'Updated product'))
        .called(1);
    verifyNoMoreInteractions(repository);
  });

  test('invalid identity or name never writes', () {
    expect(() => manage.rename(_withId(0), 'Product'), throwsFormatException);
    for (final name in ['', '  ', List.filled(129, 'a').join()]) {
      expect(() => manage.rename(detailsFixture, name), throwsFormatException);
    }
    verifyZeroInteractions(repository);
  });

  test('reprice converts comma decimals into the exact amount', () async {
    when(() => repository.updatePrice(detailsFixture, any()))
        .thenAnswer((_) async => detailsFixture);

    await manage.reprice(detailsFixture, '12,05');

    final price =
        verify(() => repository.updatePrice(detailsFixture, captureAny()))
                .captured
                .single
            as ChfPrice;
    expect(price.formatted, '12.05');
    verifyNoMoreInteractions(repository);
  });

  test('invalid price or identity never writes', () {
    expect(() => manage.reprice(_withId(0), '1'), throwsFormatException);
    for (final price in ['-1', 'NaN', '1.001', 'CHF 1', '']) {
      expect(
        () => manage.reprice(detailsFixture, price),
        throwsFormatException,
      );
    }
    verifyZeroInteractions(repository);
  });

  test('asynchronous repository failures propagate without retry', () async {
    const failure = AppFailure(FailureKind.forbidden, 'Not permitted.');
    when(() => repository.updateName(detailsFixture, 'Product'))
        .thenAnswer((_) async => throw failure);

    await expectLater(
      manage.rename(detailsFixture, 'Product'),
      throwsA(same(failure)),
    );

    verify(() => repository.updateName(detailsFixture, 'Product')).called(1);
    verifyNoMoreInteractions(repository);
  });
}
