import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/models/product_details_model.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class OdooProductDetailsRepository implements ProductDetailsRepository {
  const new(this.source, {required this.onSessionRejected});
  final ProductDetailsRemoteDataSource source;
  final Future<void> Function() onSessionRejected;

  @override
  Future<ProductCreationContext> prepareCreation(String barcode) =>
      _authenticated(() => _prepareCreation(barcode));

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
    // Original save uses `if tax_ids`, so [] otherwise inherits Odoo defaults.
    // Its existing update route supports an explicit empty tax assignment.
    if (!context.supportsCreateOnly &&
        product.taxIds.isEmpty &&
        (saved.taxIds == null || saved.taxIds!.isNotEmpty)) {
      try {
        final corrected = await updateInformation(
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
  });

  Future<T> _authenticated<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.unauthenticated ||
          error.kind == FailureKind.network ||
          error.kind == FailureKind.timeout) {
        await onSessionRejected();
      }
      rethrow;
    }
  }

  @override
  Future<ProductDetailsState> load(String barcode) =>
      _authenticated(() => _load(barcode));

  Future<ProductDetailsState> _load(String barcode) async {
    final permission = await source.call('/mupi/mobile/auth/token/check');
    final rawScopes = permission['scopes'];
    if (rawScopes != null && rawScopes != false && rawScopes is! String) {
      throw invalidResponse;
    }
    final scopes = rawScopes is String
        ? rawScopes.split(RegExp(r'\s+'))
        : <String>[];
    final result = await source.call('/mupi/mobile/api/products/find', {
      'barcode': barcode,
    });
    if (!result.containsKey('product')) throw invalidResponse;
    final product = result['product'];
    if (product != null && product is! Map<String, dynamic>) {
      throw invalidResponse;
    }
    return ProductDetailsState(
      product == null
          ? null
          : ProductDetailsModel.parse(product as Map<String, dynamic>, barcode),
      ProductAccess(
        editName: scopes.contains('product:name_update'),
        updatePrice: scopes.contains('product:price_update'),
        readReferences: scopes.contains('reference:read'),
      ),
    );
  }

  @override
  Future<void> updateName(int id, String name) => _authenticated(() async {
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
  }) => _authenticated(() async {
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
  });

  @override
  Future<ProductDetails> updatePrice(int id, double price) =>
      _authenticated(() async {
        final result = await source.call(
          '/mupi/mobile/api/products/price/update',
          {'product_id': id, 'price': price},
        );
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
