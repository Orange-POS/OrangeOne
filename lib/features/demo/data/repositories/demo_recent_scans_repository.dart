import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/recent_scans_repository.dart';

/// The demo login's recent scans: in memory only, gone when the login ends,
/// with the same limit as the real history.
class DemoRecentScansRepository implements RecentScansRepository {
  new();
  final _items = <Product>[];

  @override
  Future<List<Product>> load() async => List.unmodifiable(_items);

  @override
  Future<void> record(Product product) async {
    _items
      ..removeWhere((item) => item.barcode == product.barcode)
      ..insert(0, product);
    if (_items.length > EncryptedReadCache.recentScanLimit) {
      _items.removeRange(EncryptedReadCache.recentScanLimit, _items.length);
    }
  }
}
