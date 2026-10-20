import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';

import '../../../../support/product_details_fakes.dart';

class MockProductDetailsRepository extends Mock
    implements ProductDetailsRepository;

void main() {
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
    when(() => repository.updateName(10, 'Updated product'))
        .thenAnswer((_) async {});

    await manage.rename(10, ' Updated product ');

    verify(() => repository.updateName(10, 'Updated product')).called(1);
    verifyNoMoreInteractions(repository);
  });

  test('invalid identity or name never writes', () {
    expect(() => manage.rename(0, 'Product'), throwsFormatException);
    for (final name in ['', '  ', List.filled(201, 'a').join()]) {
      expect(() => manage.rename(10, name), throwsFormatException);
    }
    verifyZeroInteractions(repository);
  });

  test('reprice converts comma decimals into the repository amount', () async {
    when(() => repository.updatePrice(10, 12.05))
        .thenAnswer((_) async => detailsFixture);

    await manage.reprice(10, '12,05');

    verify(() => repository.updatePrice(10, 12.05)).called(1);
    verifyNoMoreInteractions(repository);
  });

  test('invalid price or identity never writes', () {
    expect(() => manage.reprice(0, '1'), throwsFormatException);
    for (final price in ['-1', 'NaN', '1.001', 'CHF 1', '']) {
      expect(() => manage.reprice(10, price), throwsFormatException);
    }
    verifyZeroInteractions(repository);
  });

  test('asynchronous repository failures propagate without retry', () async {
    const failure = AppFailure(FailureKind.forbidden, 'Not permitted.');
    when(() => repository.updateName(10, 'Product'))
        .thenAnswer((_) async => throw failure);

    await expectLater(manage.rename(10, 'Product'), throwsA(same(failure)));

    verify(() => repository.updateName(10, 'Product')).called(1);
    verifyNoMoreInteractions(repository);
  });
}
