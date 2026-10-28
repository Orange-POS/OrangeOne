import 'dart:async';

import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

const detailsFixture = ProductDetails(
  id: 10,
  name: 'Aachi Fish Fry Masala',
  barcode: '0010101010',
  price: 100,
  stock: 48,
  unit: 'Units',
  currency: 'CHF',
  category: ProductCategory(id: 4, name: 'Spices'),
  version: '3',
  stockAdjustable: true,
  stockLocationId: 8,
  quantityDecimals: 2,
);

class FakeDetailsRepository implements ProductDetailsRepository {
  NewProduct? submittedProduct;
  int creates = 0;
  Completer<ProductCreationContext>? pendingCreation;
  @override
  Future<ProductCreationContext> prepareCreation(
    String barcode, {
    bool refresh = false,
  }) async {
    if (pendingCreation != null) return await pendingCreation!.future;
    if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
    if (referencesError != null) {
      Error.throwWithStackTrace(referencesError!, StackTrace.current);
    }
    return ProductCreationContext(
      details: ProductDetailsState(
        product?.barcode == barcode ? product : null,
        access,
      ),
      taxes: taxes,
      defaultTaxIds: defaultTaxIds,
      categories: categories,
    );
  }

  @override
  Future<ProductDetails> createProduct(NewProduct draft) async {
    creates++;
    submittedProduct = draft;
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, StackTrace.current);
    }
    if (pendingWrite != null) return await pendingWrite!.future;
    return product = ProductDetails(
      id: 11,
      barcode: draft.barcode,
      name: draft.name,
      price: draft.price.asDouble,
      stock: 0,
      unit: 'Units',
      taxIds: draft.taxIds,
      version: '1',
      taxes: taxes
          .where((tax) => draft.taxIds.contains(tax.id))
          .map((tax) => tax.label)
          .toList(),
    );
  }

  ProductDetails? product = detailsFixture;
  ProductAccess access = const ProductAccess(
    createProduct: true,
    editName: true,
    updatePrice: true,
    readReferences: true,
    updateTaxes: true,
    updateCategory: true,
    createCategory: true,
    adjustStock: true,
  );
  List<ProductTax> taxes = const [ProductTax(id: 1, label: 'VAT (15%)')];
  List<ProductCategory> categories = const [
    ProductCategory(id: 4, name: 'Spices'),
    ProductCategory(id: 5, name: 'Drinks'),
  ];
  List<int> defaultTaxIds = const [];
  int categoryCreates = 0;
  Object? categoryError;
  List<int>? writtenTaxIds;
  CategoryChange? writtenCategory;
  String? writtenName;

  /// Versions sent with updates (If-Match), in order.
  final writtenVersions = <String?>[];
  Object? referencesError;
  @override
  Future<List<ProductTax>> loadTaxes() async {
    if (referencesError != null) {
      Error.throwWithStackTrace(referencesError!, StackTrace.current);
    }
    return taxes;
  }

  @override
  Future<ProductCategory> createCategory(String name) async {
    categoryCreates++;
    if (categoryError != null) {
      Error.throwWithStackTrace(categoryError!, StackTrace.current);
    }
    final created = ProductCategory(id: 100 + categoryCreates, name: name);
    categories = [...categories, created];
    return created;
  }

  @override
  Future<List<ProductCategory>> loadCategories() async {
    if (referencesError != null) {
      Error.throwWithStackTrace(referencesError!, StackTrace.current);
    }
    return categories;
  }

  static String _next(String? version) =>
      '${(int.tryParse(version ?? '') ?? 0) + 1}';

  @override
  Future<ProductDetails> updateInformation(
    ProductDetails current, {
    String? name,
    List<int>? taxIds,
    CategoryChange? category,
  }) async {
    writes++;
    writtenName = name;
    writtenTaxIds = taxIds;
    writtenCategory = category;
    writtenVersions.add(current.version);
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, StackTrace.current);
    }
    if (pendingWrite != null) return await pendingWrite!.future;
    final previous = product!;
    return product = ProductDetails(
      id: previous.id,
      name: name ?? previous.name,
      barcode: previous.barcode,
      price: previous.price,
      stock: previous.stock,
      unit: previous.unit,
      reference: previous.reference,
      taxes: taxIds == null
          ? previous.taxes
          : taxes
                .where((tax) => taxIds.contains(tax.id))
                .map((tax) => tax.label)
                .toList(),
      taxIds: taxIds ?? previous.taxIds,
      currency: previous.currency,
      category: category == null
          ? previous.category
          : categories.where((c) => c.id == category.id).firstOrNull,
      version: _next(previous.version),
    );
  }

  Object? error;
  Completer<ProductDetailsState>? pending;
  int loads = 0;
  int writes = 0;
  Object? writeError;
  Completer<ProductDetails>? pendingWrite;
  @override
  Future<ProductDetailsState> load(String barcode) async {
    loads++;
    if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
    if (pending != null) return await pending!.future;
    return ProductDetailsState(product, access);
  }

  ProductPage page = const ProductPage([], null);
  final searches = <({String? query, int? categoryId, String? cursor})>[];
  @override
  Future<ProductPage> searchProducts({
    String? query,
    int? categoryId,
    String? cursor,
    int limit = 25,
  }) async {
    searches.add((query: query, categoryId: categoryId, cursor: cursor));
    if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
    return page;
  }

  StockCount? writtenCount;
  @override
  Future<StockAdjustment> adjustStock(
    ProductDetails current,
    StockCount count,
  ) async {
    writes++;
    writtenCount = count;
    writtenVersions.add(current.version);
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, StackTrace.current);
    }
    if (pendingWrite != null) {
      final written = await pendingWrite!.future;
      return StockAdjustment(
        product: written,
        previousQuantity: current.stock ?? 0,
        newQuantity: count.quantity,
      );
    }
    final previous = product!;
    product = ProductDetails(
      id: previous.id,
      name: previous.name,
      barcode: previous.barcode,
      price: previous.price,
      stock: count.quantity,
      unit: previous.unit,
      reference: previous.reference,
      taxes: previous.taxes,
      taxIds: previous.taxIds,
      currency: previous.currency,
      category: previous.category,
      version: _next(previous.version),
      stockAdjustable: previous.stockAdjustable,
      stockLocationId: previous.stockLocationId,
      quantityDecimals: previous.quantityDecimals,
    );
    return StockAdjustment(
      product: product!,
      previousQuantity: previous.stock ?? 0,
      newQuantity: count.quantity,
    );
  }

  @override
  Future<ProductDetails> updateName(ProductDetails current, String name) =>
      updateInformation(current, name: name);

  @override
  Future<ProductDetails> updatePrice(
    ProductDetails current,
    ChfPrice price,
  ) async {
    writes++;
    writtenVersions.add(current.version);
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, StackTrace.current);
    }
    if (pendingWrite != null) return await pendingWrite!.future;
    final previous = product!;
    return product = ProductDetails(
      id: previous.id,
      name: previous.name,
      barcode: previous.barcode,
      price: price.asDouble,
      stock: previous.stock,
      unit: previous.unit,
      reference: previous.reference,
      taxes: previous.taxes,
      taxIds: previous.taxIds,
      currency: previous.currency,
      category: previous.category,
      version: _next(previous.version),
    );
  }
}
