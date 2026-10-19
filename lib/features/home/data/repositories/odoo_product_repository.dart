import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/models/product_model.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';

class OdooProductRepository implements ProductRepository {
  const new(this._remote, {required this.onSessionRejected});
  final ProductRemoteDataSource _remote;
  final Future<void> Function() onSessionRejected;

  @override
  Future<Product?> findByBarcode(String barcode) async {
    try {
      final result = await _remote.find(barcode);
      ProductRemoteDataSource.checkResult(result);
      if (!result.containsKey('product')) throw invalidResponse;
      final product = result['product'];
      if (product == null) return null;
      // The confirmed backend uses search(limit=1), never an array of matches.
      if (product is! Map<String, dynamic>) throw invalidResponse;
      return ProductModel.fromJson(product, barcode);
    } on AppFailure catch (failure) {
      if (failure.kind == FailureKind.unauthenticated ||
          failure.kind == FailureKind.network ||
          failure.kind == FailureKind.timeout) {
        await onSessionRejected();
      }
      rethrow;
    }
  }
}
