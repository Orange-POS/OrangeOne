import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/models/product_details_model.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class OdooProductDetailsRepository implements ProductDetailsRepository {
  new(this.source, {required this.onSessionRejected, this.cache});
  final EncryptedReadCache? cache;
  final ProductDetailsRemoteDataSource source;
  final Future<void> Function() onSessionRejected;
  final _loads = <String, Future<ProductDetailsState>>{};

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
    if (!details.access.editName ||
        !details.access.updatePrice ||
        !details.access.readReferences ||
        details.product != null) {
      return ProductCreationContext(
        details: details,
        taxes: const [],
        supportsCreateOnly: false,
      );
    }
    final references = await source.call(
      '/mupi/mobile/api/products/references',
    );
    return ProductCreationContext(
      details: details,
      taxes: _parseTaxes(references),
      supportsCreateOnly: references['create_only_supported'] == true,
    );
  }

  @override
  Future<ProductDetails> createProduct(
    NewProduct product,
  ) => _authenticated(() async {
    // Both versions use the supplied save route. Prefer its stronger guard when
    // advertised; the original addon accepts only the original parameters.
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
        'Product creation is not available for this session or server.',
      );
    }
    if (product.taxIds.any((id) => !context.taxes.any((tax) => tax.id == id))) {
      throw const AppFailure(
        FailureKind.validation,
        'Tax options changed. Reload the form.',
      );
    }
    Future<ProductDetails> save() async {
      final result = await source.call('/mupi/mobile/api/products/save', {
        'barcode': product.barcode,
        'name': product.name,
        'price': product.price.asDouble,
        'tax_ids': product.taxIds,
        if (context.supportsCreateOnly) 'create_only': true,
      });
      final created = context.supportsCreateOnly
          ? result['action'] == 'created'
          : result['action'] == 'created' ||
                (!result.containsKey('action') &&
                    result['message'] == 'Product created successfully.');
      if (!created || result['product'] is! Map<String, dynamic>) {
        throw invalidResponse;
      }
      final saved = ProductDetailsModel.parse(
        result['product'] as Map<String, dynamic>,
        product.barcode,
      );
      // Original save uses `if tax_ids`; [] otherwise inherits defaults.
      // Its existing update route supports an explicit empty tax assignment.
      if (!context.supportsCreateOnly &&
          product.taxIds.isEmpty &&
          (saved.taxIds == null || saved.taxIds!.isNotEmpty)) {
        try {
          final corrected = await _updateInformation(
            saved.id,
            saved.name,
            taxIds: const [],
          );
          if (corrected.barcode != product.barcode ||
              corrected.taxIds == null ||
              corrected.taxIds!.isNotEmpty) {
            throw invalidResponse;
          }
          return corrected;
        } on Exception {
          throw const AppFailure(
            FailureKind.protocol,
            'The product was saved, but its tax selection '
            'could not be confirmed. '
            'Check product details before trying again.',
          );
        }
      }
      return saved;
    }

    return await (cache == null ? save() : cache!.write(save));
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
      final permission = await source.call('/mupi/mobile/auth/token/check');
      final rawScopes = permission['scopes'];
      if (rawScopes != null && rawScopes != false && rawScopes is! String) {
        throw invalidResponse;
      }
      final scopes = rawScopes is String
          ? rawScopes.split(RegExp(r'\s+'))
          : <String>[];
      access = ProductAccess(
        editName: scopes.contains('product:name_update'),
        updatePrice: scopes.contains('product:price_update'),
        readReferences: scopes.contains('reference:read'),
      );
      final result = await source.call('/mupi/mobile/api/products/find', {
        'barcode': barcode,
      });
      if (!result.containsKey('product')) throw invalidResponse;
      final product = result['product'];
      if (product == null) return null;
      if (product is! Map<String, dynamic>) throw invalidResponse;
      ProductDetailsModel.parse(product, barcode);
      return product;
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

  Future<T> _write<T>(Future<T> Function() operation) => _authenticated(
    () => cache == null ? operation() : cache!.write(operation),
  );

  @override
  Future<void> updateName(int id, String name) => _write(() async {
    await source.call('/mupi/mobile/api/products/name/update', {
      'product_id': id,
      'name': name,
    });
  });

  @override
  Future<List<ProductTax>> loadTaxes() => _authenticated(() async {
    final result = await source.call('/mupi/mobile/api/products/references');
    return _parseTaxes(result);
  });

  List<ProductTax> _parseTaxes(Map<String, dynamic> result) {
    final raw = result['taxes'];
    if (raw is! List) throw invalidResponse;
    final taxes = <ProductTax>[];
    final ids = <int>{};
    for (final item in raw) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! int ||
          (item['id'] as int) <= 0 ||
          item['name'] is! String ||
          (item['name'] as String).trim().isEmpty ||
          item['amount'] is! num ||
          !(item['amount'] as num).isFinite ||
          item['amount_type'] is! String ||
          !ids.add(item['id'] as int)) {
        throw invalidResponse;
      }
      taxes.add(
        ProductTax(
          id: item['id'] as int,
          label: item['amount_type'] == 'percent'
              ? '${item['name']} (${item['amount']}%)'
              : item['name'] as String,
        ),
      );
    }
    return List.unmodifiable(taxes);
  }

  @override
  Future<ProductDetails> updateInformation(
    int id,
    String name, {
    List<int>? taxIds,
  }) => _write(() => _updateInformation(id, name, taxIds: taxIds));

  Future<ProductDetails> _updateInformation(
    int id,
    String name, {
    List<int>? taxIds,
  }) async {
    final result = await source.call('/mupi/mobile/api/products/update', {
      'product_id': id,
      'name': name,
      'tax_ids': ?taxIds,
    });
    final product = result['product'];
    if (product is! Map<String, dynamic> ||
        product['id'] != id ||
        product['barcode'] is! String ||
        (product['barcode'] as String).isEmpty) {
      throw invalidResponse;
    }
    return ProductDetailsModel.parse(product, product['barcode'] as String);
  }

  @override
  Future<ProductDetails> updatePrice(int id, double price) => _write(() async {
    final result = await source.call('/mupi/mobile/api/products/price/update', {
      'product_id': id,
      'price': price,
    });
    final product = result['product'];
    if (product is! Map<String, dynamic> ||
        product['id'] != id ||
        product['barcode'] is! String ||
        (product['barcode'] as String).isEmpty) {
      throw invalidResponse;
    }
    return ProductDetailsModel.parse(product, product['barcode'] as String);
  });
}
