import 'package:orange_one/features/home/domain/entities/product.dart';

abstract interface class ProductRepository {
  /// Null means the authoritative backend found no matching POS product.
  /// Explicit read-only retries may probe while offline; normal reads do not.
  Future<Product?> findByBarcode(String barcode, {bool refresh = false});
}
