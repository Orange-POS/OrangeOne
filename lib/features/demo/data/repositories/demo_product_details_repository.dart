import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/demo/data/repositories/demo_catalog.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

/// Product details, search, creation, price and stock changes against the
/// Demo Mode sample inventory. Versions guard updates like the backend does.
class DemoProductDetailsRepository implements ProductDetailsRepository {
  const new(this._catalog, {required this.canEdit});
  final DemoCatalog _catalog;

  /// False for the read-only sample: every restricted action is disabled.
  final bool canEdit;

  ProductAccess get _access => ProductAccess(
    editName: canEdit,
    updatePrice: canEdit,
    readReferences: canEdit,
    updateTaxes: canEdit,
    updateCategory: canEdit,
    createProduct: canEdit,
    createCategory: canEdit,
    adjustStock: canEdit,
  );

  @override
  Future<ProductDetailsState> load(String barcode) async =>
      ProductDetailsState(_catalog.byBarcode(barcode), _access);

  @override
  Future<ProductCreationContext> prepareCreation(
    String barcode, {
    bool refresh = false,
  }) async => ProductCreationContext(
    details: await load(barcode),
    taxes: List.of(_catalog.taxes),
    defaultTaxIds: const [1],
    categories: List.of(_catalog.categories),
  );

  @override
  Future<ProductDetails> createProduct(NewProduct product) async =>
      _catalog.create(
        barcode: product.barcode,
        name: product.name,
        price: product.price.asDouble,
        taxIds: product.taxIds,
        categoryId: product.categoryId,
        stock: product.initialQuantity?.quantity,
      );

  @override
  Future<ProductPage> searchProducts({
    String? query,
    int? categoryId,
    String? cursor,
    int limit = 25,
  }) async {
    final matches = _catalog.search(query: query, categoryId: categoryId);
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = start + limit;
    return ProductPage([
      for (final product in matches.skip(start).take(limit))
        ProductSummary(
          id: product.id,
          name: product.name,
          barcode: product.barcode,
          price: product.price,
          currency: 'CHF',
          stock: product.stock,
        ),
    ], end < matches.length ? '$end' : null);
  }

  @override
  Future<ProductDetails> updateName(
    ProductDetails product,
    String name,
  ) async => _catalog.rename(product, name);

  @override
  Future<ProductDetails> updatePrice(
    ProductDetails product,
    ChfPrice price,
  ) async => _catalog.reprice(product, price.asDouble);

  @override
  Future<List<ProductTax>> loadTaxes() async => List.of(_catalog.taxes);

  @override
  Future<StockAdjustment> adjustStock(
    ProductDetails product,
    StockCount count, {
    StockOperation operation = StockOperation.update,
  }) async {
    if (!product.stockAdjustable) {
      throw const AppFailure(
        FailureKind.validation,
        'Stock for this product cannot be counted here.',
      );
    }
    final amount = count.quantity;
    if (operation == StockOperation.remove && amount > (product.stock ?? 0)) {
      throw const AppFailure(
        FailureKind.validation,
        'You cannot remove more than the stock on hand.',
      );
    }
    final change = _catalog.setStock(
      product,
      (current) => operation.resultFor(current, amount),
    );
    return StockAdjustment(
      product: change.product,
      previousQuantity: change.before,
      newQuantity: change.product.stock ?? 0,
      operation: operation,
    );
  }

  @override
  Future<List<ProductCategory>> loadCategories() async =>
      List.of(_catalog.categories);

  @override
  Future<ProductCategory> createCategory(String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 64) {
      throw const AppFailure(
        FailureKind.validation,
        'Enter a category name of 1–64 characters.',
      );
    }
    return _catalog.createCategory(value);
  }

  @override
  Future<ProductDetails> updateInformation(
    ProductDetails product, {
    String? name,
    List<int>? taxIds,
    CategoryChange? category,
  }) async => _catalog.updateInformation(
    product,
    name: name,
    taxIds: taxIds,
    categoryId: category?.id,
    changeCategory: category != null,
  );
}
