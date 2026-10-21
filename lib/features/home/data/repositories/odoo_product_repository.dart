import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/models/product_model.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';

class OdooProductRepository implements ProductRepository {
  const new(this._remote, {required this.onSessionRejected, this.cache});
  final EncryptedReadCache? cache;
  final ProductRemoteDataSource _remote;
  final Future<void> Function() onSessionRejected;

  @override
  Future<Product?> findByBarcode(String barcode, {bool refresh = false}) async {
    try {
      if (refresh) cache?.retryRead();
      Future<Map<String, dynamic>?> fetch() async {
        final result = await _remote.find(barcode);
        ProductRemoteDataSource.checkResult(result);
        if (!result.containsKey('product')) throw invalidResponse;
        final product = result['product'];
        if (product == null) return null;
        if (product is! Map<String, dynamic>) throw invalidResponse;
        ProductModel.fromJson(product, barcode);
        return product;
      }

      final product = cache == null
          ? await fetch()
          : await cache!.load(barcode, fetch);
      return product == null ? null : ProductModel.fromJson(product, barcode);
    } on AppFailure catch (failure) {
      if (failure.kind == FailureKind.unauthenticated ||
          (cache == null &&
              (failure.kind == FailureKind.network ||
                  failure.kind == FailureKind.timeout))) {
        await onSessionRejected();
      }
      rethrow;
    }
  }
}
