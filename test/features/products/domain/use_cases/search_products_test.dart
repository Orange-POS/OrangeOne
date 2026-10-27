import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/products/domain/use_cases/search_products.dart';

import '../../../../support/product_details_fakes.dart';

void main() {
  late FakeDetailsRepository repository;
  late SearchProducts search;
  setUp(() {
    repository = FakeDetailsRepository();
    search = SearchProducts(repository);
  });

  test('trims the query and forwards filters and cursor', () async {
    await search(query: '  masala ', categoryId: 4, cursor: 'c2');
    expect(repository.searches.single, (
      query: 'masala',
      categoryId: 4,
      cursor: 'c2',
    ));
  });

  test('a blank query searches by category only', () async {
    await search(query: '   ', categoryId: 4);
    expect(repository.searches.single.query, isNull);
  });

  for (final (query, categoryId, limit) in [
    ('m', null, 25),
    ('x' * 65, null, 25),
    (null, 0, 25),
    (null, null, 0),
    (null, null, 101),
  ]) {
    test('rejects query=$query category=$categoryId limit=$limit', () {
      expect(
        () => search(query: query, categoryId: categoryId, limit: limit),
        throwsFormatException,
      );
      expect(repository.searches, isEmpty);
    });
  }
}
