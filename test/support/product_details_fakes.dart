import 'dart:async';

import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

const detailsFixture = ProductDetails(
  id: 10,
  name: 'Aachi Fish Fry Masala',
  barcode: '0010101010',
  price: 100,
  stock: 48,
  unit: 'Units',
);

class FakeDetailsRepository implements ProductDetailsRepository {
  bool supportsCreateOnly = true;
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
      supportsCreateOnly: supportsCreateOnly,
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
  );
  List<ProductTax> taxes = const [ProductTax(id: 1, label: 'VAT (15%)')];
  List<int>? writtenTaxIds;
  Object? referencesError;
  @override
  Future<List<ProductTax>> loadTaxes() async {
    if (referencesError != null) {
      Error.throwWithStackTrace(referencesError!, StackTrace.current);
    }
    return taxes;
  }

  @override
  Future<ProductDetails> updateInformation(
    int id,
    String name, {
    List<int>? taxIds,
  }) async {
    writes++;
    writtenTaxIds = taxIds;
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, StackTrace.current);
    }
    if (pendingWrite != null) return await pendingWrite!.future;
    final previous = product!;
    return product = ProductDetails(
      id: previous.id,
      name: name,
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

  @override
  Future<void> updateName(int id, String name) async {
    writes++;
  }

  @override
  Future<ProductDetails> updatePrice(int id, double price) async {
    writes++;
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, StackTrace.current);
    }
    if (pendingWrite != null) return await pendingWrite!.future;
    final previous = product!;
    return product = ProductDetails(
      id: previous.id,
      name: previous.name,
      barcode: previous.barcode,
      price: price,
      stock: previous.stock,
      unit: previous.unit,
      reference: previous.reference,
      taxes: previous.taxes,
      taxIds: previous.taxIds,
    );
  }
}
