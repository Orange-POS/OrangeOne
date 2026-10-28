import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

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

  /// Updates are guarded by [ProductDetails.version] of the given, freshly
  /// verified product; a stale version fails as a conflict and nothing is
  /// overwritten.
  Future<ProductDetails> updateName(ProductDetails product, String name);
  Future<ProductDetails> updatePrice(ProductDetails product, ChfPrice price);
  Future<List<ProductTax>> loadTaxes();

  /// Sets the absolute counted quantity at the POS stock location, guarded
  /// by the verified product version like other updates.
  Future<StockAdjustment> adjustStock(ProductDetails product, StockCount count);
  Future<List<ProductCategory>> loadCategories();

  /// Creates a category (`POST /categories`); needs `category_create`.
  Future<ProductCategory> createCategory(String name);

  /// Sends only the given fields: [taxIds] `[]` removes all taxes, and a
  /// [category] with a null id removes the category.
  Future<ProductDetails> updateInformation(
    ProductDetails product, {
    String? name,
    List<int>? taxIds,
    CategoryChange? category,
  });
}
