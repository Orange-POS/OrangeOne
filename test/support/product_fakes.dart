import 'dart:async';

import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';

const fixtureProduct = Product(
  id: 10,
  name: 'Aachi Fish Fry Masala',
  barcode: '0010101010',
  price: 100,
  stockQuantity: 48,
  unit: 'Units',
  reference: 'MASALA',
);

Map<String, dynamic> productJson() => {
  'id': 10,
  'name': fixtureProduct.name,
  'barcode': fixtureProduct.barcode,
  'price': 100,
  'stock_quantity': 48,
  'uom': 'Units',
  'default_code': 'MASALA',
  'company_id': false,
  'active': true,
  'taxes': <Object?>[],
};

class FakeProductRepository implements ProductRepository {
  Product? product = fixtureProduct;
  AppFailure? failure;
  Completer<Product?>? pending;
  final barcodes = <String>[];

  @override
  Future<Product?> findByBarcode(String barcode, {bool refresh = false}) async {
    barcodes.add(barcode);
    if (failure != null) throw failure!;
    if (pending != null) return await pending!.future;
    return product;
  }
}
