import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/models/product_details_model.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class OdooProductDetailsRepository implements ProductDetailsRepository {
  const new(this.source, {required this.onSessionRejected});
  final ProductDetailsRemoteDataSource source;
  final Future<void> Function() onSessionRejected;

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
  Future<ProductDetailsState> load(String barcode) => _authenticated(() async {
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
  });

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
  });

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
