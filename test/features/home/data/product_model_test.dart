import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/home/data/models/product_model.dart';

Map<String, dynamic> _json({Object? category}) => {
  'id': 1,
  'name': 'Product',
  'barcode': 'BC-1',
  'price': 2.5,
  'stock_quantity': 3,
  'category': ?category,
};

void main() {
  test('the category name is read from the product record', () {
    final product = ProductModel.fromJson(
      _json(category: {'id': 4, 'name': ' Spices '}),
      'BC-1',
    );
    expect(product.category, 'Spices');
  });

  test('a missing, null or blank category is null', () {
    expect(ProductModel.fromJson(_json(), 'BC-1').category, isNull);
    expect(
      ProductModel.fromJson(_json(category: false), 'BC-1').category,
      isNull,
    );
    expect(
      ProductModel.fromJson(
        _json(category: {'id': 4, 'name': '  '}),
        'BC-1',
      ).category,
      isNull,
    );
  });
}
