import 'dart:convert';

import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/idempotency_keys.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/network/product_payload.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/models/product_access_model.dart';
import 'package:orange_one/features/products/data/models/product_details_model.dart';
import 'package:orange_one/features/products/data/models/product_reference_model.dart';
import 'package:orange_one/features/products/data/models/product_summary_model.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

/// A server-verified product read, kept in memory for conditional refresh.
typedef _ProductRead = ({
  int id,
  String? etag,
  Map<String, dynamic> record,
  ProductAccess access,
});

/// Products through Mobile API v2. Writes carry an `Idempotency-Key`, and
/// updates of existing products an `If-Match` with the product JSON
/// `version` the caller last verified (never the ETag).
class OdooProductDetailsRepository implements ProductDetailsRepository {
  new(
    this.catalog, {
    required this.onSessionRejected,
    this.cache,
    IdempotencyKeys? idempotencyKeys,
  }) : _keys = idempotencyKeys ?? IdempotencyKeys();
  final EncryptedReadCache? cache;
  final ProductCatalogRemoteDataSource catalog;
  final Future<void> Function() onSessionRejected;
  final IdempotencyKeys _keys;
  final _loads = <String, Future<ProductDetailsState>>{};

  /// Latest verified read per barcode. Permissions and versions stay in
  /// memory only; the offline cache never stores them.
  final _reads = <String, _ProductRead>{};
  static const _maxReads = 50;

  @override
  Future<ProductCreationContext> prepareCreation(
    String barcode, {
    bool refresh = false,
  }) => _authenticated(() {
    if (refresh) cache?.retryRead();
    return _prepareCreation(barcode);
  });

  Future<ProductCreationContext> _prepareCreation(String barcode) async {
    final details = await _load(barcode);
    final context = ProductCreationContext(
      details: details,
      taxes: const [],
      supportsCreateOnly: true,
    );
    if (!context.canCreate) return context;
    return ProductCreationContext(
      details: details,
      taxes: await _loadTaxes(),
      supportsCreateOnly: true,
    );
  }

  @override
  Future<ProductDetails> createProduct(NewProduct product) =>
      _authenticated(() async {
        // Recheck permissions, the barcode and the tax options before writing.
        final context = await _prepareCreation(product.barcode);
        if (context.details.product != null) {
          throw const AppFailure(
            FailureKind.conflict,
            'This barcode already exists. Open its product details.',
          );
        }
        if (!context.canCreate) {
          throw const AppFailure(
            FailureKind.forbidden,
            'Product creation is not available for this session.',
          );
        }
        if (product.taxIds.any(
          (id) => !context.taxes.any((tax) => tax.id == id),
        )) {
          throw const AppFailure(
            FailureKind.validation,
            'Tax options changed. Reload the form.',
          );
        }
        final body = {
          'barcode': product.barcode,
          'name': product.name,
          'list_price': product.price.formatted,
          // An empty list is the explicit "No Tax" choice.
          'tax_ids': product.taxIds,
        };
        return await _write(
          'POST /products',
          body,
          (key) => catalog.create(body, idempotencyKey: key),
          barcode: product.barcode,
        );
      });

  Future<T> _authenticated<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.unauthenticated ||
          (cache == null &&
              (error.kind == FailureKind.network ||
                  error.kind == FailureKind.timeout))) {
        await onSessionRejected();
      }
      rethrow;
    }
  }

  @override
  Future<ProductDetailsState> load(String barcode) async =>
      await (_loads[barcode] ??= _authenticated(
        () => _load(barcode),
      ).whenComplete(() => _loads.removeWhere((key, value) => key == barcode)));

  Future<ProductDetailsState> _load(String barcode) async {
    var access = const ProductAccess();
    Future<Map<String, dynamic>?> fetch() async {
      final read = await _read(barcode);
      if (read == null) {
        access = ProductAccessModel.parse(await catalog.sessionPermissions());
        return null;
      }
      access = read.access;
      return read.record;
    }

    final result = cache == null
        ? (product: await fetch(), serverVerified: true)
        : await cache!.loadResult(barcode, fetch);
    final product = result.product;
    return ProductDetailsState(
      product == null ? null : ProductDetailsModel.parse(product, barcode),
      result.serverVerified ? access : const ProductAccess(),
    );
  }

  /// Refreshes a known product by id with `If-None-Match` (304 keeps the
  /// previous read); otherwise, or when the product no longer carries this
  /// barcode, looks it up by barcode. Null means `PRODUCT_NOT_FOUND`.
  Future<_ProductRead?> _read(String barcode) async {
    final previous = _reads.remove(barcode);
    if (previous != null) {
      try {
        final response = await catalog.byId(previous.id, etag: previous.etag);
        if (response.notModified) {
          if (previous.etag == null) throw invalidResponse;
          return _remember(barcode, previous);
        }
        final read = _parse(response);
        if (read.record['barcode'] == barcode) return _remember(barcode, read);
      } on AppFailure catch (failure) {
        if (failure.kind != FailureKind.notFound) rethrow;
      }
    }
    try {
      final read = _parse(await catalog.byBarcode(barcode));
      if (read.record['barcode'] != barcode) throw invalidResponse;
      return _remember(barcode, read);
    } on AppFailure catch (failure) {
      if (failure.code == 'PRODUCT_NOT_FOUND') return null;
      rethrow;
    }
  }

  _ProductRead _remember(String barcode, _ProductRead read) {
    _reads[barcode] = read;
    if (_reads.length > _maxReads) _reads.remove(_reads.keys.first);
    return read;
  }

  static _ProductRead _parse(MobileApiResponse response) {
    final record = ProductPayload.productRecord(response.data);
    return (
      id: record['id'] as int,
      etag: response.etag,
      record: record,
      access: ProductAccessModel.parse(record['permissions']),
    );
  }

  @override
  Future<ProductPage> searchProducts({
    String? query,
    int? categoryId,
    String? cursor,
    int limit = 25,
  }) => _authenticated(() async {
    final response = await catalog.search(
      query: query,
      categoryId: categoryId,
      cursor: cursor,
      limit: limit,
    );
    return ProductSummaryModel.page(response.data, response.meta);
  });

  /// Sends one write with an idempotency key for this exact [operation] and
  /// [body]. Writes need a server-verified connection: the cache rejects
  /// them while offline and invalidates snapshots before sending.
  Future<ProductDetails> _write(
    String operation,
    Map<String, dynamic> body,
    Future<MobileApiResponse> Function(String key) send, {
    required String barcode,
  }) {
    Future<ProductDetails> run() =>
        _keys.run('$operation ${jsonEncode(body)}', (key) async {
          final response = await send(key);
          final read = _parse(response);
          if (read.record['barcode'] != barcode) throw invalidResponse;
          final product = ProductDetailsModel.parse(read.record, barcode);
          _remember(barcode, read);
          return product;
        });
    return cache == null ? run() : cache!.write(run);
  }

  /// Updates an existing product guarded by its verified [product] version.
  Future<ProductDetails> _update(
    ProductDetails product,
    String operation,
    Map<String, dynamic> body,
    Future<MobileApiResponse> Function(String version, String key) send,
  ) => _authenticated(() async {
    final version = product.version;
    if (version == null) {
      throw const AppFailure(
        FailureKind.network,
        'Reconnect and refresh this product before changing it.',
      );
    }
    try {
      return await _write(
        '$operation "$version"',
        body,
        (key) => send(version, key),
        barcode: product.barcode,
      );
    } on AppFailure catch (failure) {
      if (failure.code != 'VERSION_CONFLICT') rethrow;
      // Never overwrite: the caller reloads and the user decides again.
      _reads.remove(product.barcode);
      throw AppFailure(
        FailureKind.conflict,
        'This product was changed on another device. '
        'Review the current information and try again.',
        code: failure.code,
        requestId: failure.requestId,
      );
    }
  });

  @override
  Future<ProductDetails> updateName(ProductDetails product, String name) =>
      updateInformation(product, name: name);

  @override
  Future<ProductDetails> updateInformation(
    ProductDetails product, {
    String? name,
    List<int>? taxIds,
    CategoryChange? category,
  }) {
    final body = {
      'name': ?name,
      'tax_ids': ?taxIds,
      if (category != null) 'category_id': category.id,
    };
    if (body.isEmpty) {
      throw const FormatException('Change at least one product field.');
    }
    return _update(
      product,
      'PATCH /products/${product.id}',
      body,
      (version, key) => catalog.update(
        product.id,
        body,
        version: version,
        idempotencyKey: key,
      ),
    );
  }

  @override
  Future<ProductDetails> updatePrice(ProductDetails product, ChfPrice price) =>
      _update(
        product,
        'PUT /products/${product.id}/price',
        {'list_price': price.formatted},
        (version, key) => catalog.updatePrice(
          product.id,
          price.formatted,
          version: version,
          idempotencyKey: key,
        ),
      );

  @override
  Future<List<ProductTax>> loadTaxes() => _authenticated(_loadTaxes);

  Future<List<ProductTax>> _loadTaxes() async =>
      ProductReferenceModel.taxes(await catalog.taxes());

  @override
  Future<List<ProductCategory>> loadCategories() => _authenticated(() async {
    final response = await catalog.categories();
    return ProductReferenceModel.categories(response.data);
  });
}
