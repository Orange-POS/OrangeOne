import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/recent_scans_repository.dart';

/// Recent scans kept in the session's encrypted read cache, so they survive
/// app restarts, belong to one session and are deleted with it. Without a
/// cache (signed out) nothing is stored.
class CachedRecentScansRepository implements RecentScansRepository {
  const new(this._cache);
  final EncryptedReadCache? _cache;

  @override
  Future<List<Product>> load() async {
    try {
      final records = await _cache?.readRecents() ?? const [];
      return [for (final record in records) _product(record)];
    } on Exception {
      return const [];
    }
  }

  @override
  Future<void> record(Product product) async {
    try {
      await _cache?.recordRecent({
        'id': product.id,
        'name': product.name,
        'barcode': product.barcode,
        'price': product.price,
        'stock_quantity': product.stockQuantity,
        'uom': product.unit,
        'category': product.category,
      });
    } on Exception {
      // Best effort.
    }
  }

  static Product _product(Map<String, dynamic> record) => Product(
    id: record['id'] as int,
    name: record['name'] as String,
    barcode: record['barcode'] as String,
    price: (record['price'] as num).toDouble(),
    stockQuantity: (record['stock_quantity'] as num?)?.toDouble(),
    unit: record['uom'] as String? ?? '',
    category: record['category'] as String?,
  );
}

/// In-memory history for runs without a session cache (and tests).
class MemoryRecentScansRepository implements RecentScansRepository {
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
