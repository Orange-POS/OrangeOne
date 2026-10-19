import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';
import 'package:orange_one/features/home/domain/use_cases/lookup_product.dart';

import '../../../../support/product_fakes.dart';

class MockProductRepository extends Mock implements ProductRepository;

void main() {
  late MockProductRepository repository;
  late LookupProduct lookup;
  setUp(() {
    repository = MockProductRepository();
    lookup = LookupProduct(repository);
  });
  test('trims input while preserving leading zeros and case', () async {
    when(() => repository.findByBarcode('00Ab12'))
        .thenAnswer((_) async => fixtureProduct);
    expect(await lookup(' 00Ab12 '), fixtureProduct);
    verify(() => repository.findByBarcode('00Ab12')).called(1);
  });
  test('invalid input never reaches the repository', () {
    for (final value in [
      '',
      '  ',
      'bad\u0000code',
      List.filled(257, 'a').join(),
    ]) {
      expect(() => lookup(value), throwsFormatException);
    }
    verifyZeroInteractions(repository);
  });
  test('unknown product is a valid empty lookup', () async {
    when(() => repository.findByBarcode('unknown'))
        .thenAnswer((_) async => null);
    expect(await lookup('unknown'), isNull);
  });
  test('typed repository failure is preserved for the controller', () async {
    const failure = AppFailure(FailureKind.network, 'Server unavailable');
    when(() => repository.findByBarcode('123')).thenThrow(failure);
    expect(() => lookup('123'), throwsA(same(failure)));
  });
}
