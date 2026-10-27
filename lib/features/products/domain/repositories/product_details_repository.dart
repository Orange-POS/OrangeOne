import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';

abstract interface class ProductDetailsRepository {
  /// Explicit checks request an authoritative read without performing writes.
  Future<ProductCreationContext> prepareCreation(
    String barcode, {
    bool refresh = false,
  });
  Future<ProductDetails> createProduct(NewProduct product);
  Future<ProductDetailsState> load(String barcode);

  /// One page of POS products matching [query] and/or [categoryId].
  Future<ProductPage> searchProducts({
    String? query,
    int? categoryId,
    String? cursor,
    int limit = 25,
  });
  Future<void> updateName(int id, String name);
  Future<ProductDetails> updatePrice(int id, double price);
  Future<List<ProductTax>> loadTaxes();
  Future<ProductDetails> updateInformation(
    int id,
    String name, {
    List<int>? taxIds,
  });
}
