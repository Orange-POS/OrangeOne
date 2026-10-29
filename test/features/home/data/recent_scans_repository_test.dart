import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/home/data/repositories/recent_scans_repositories.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';

Product _product(
  int id, {
  double price = 10,
  double? stock = 4,
  String reference = 'REF',
}) => Product(
  id: id,
  name: 'Product $id',
  barcode: 'BC-$id',
  price: price,
  stockQuantity: stock,
  unit: 'Units',
  reference: reference,
);

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  setUp(() {
    database = ReadCacheDatabase(NativeDatabase.memory());
    cache = EncryptedReadCache(database, sessionSecret: 'repo');
  });
  tearDown(() async {
    await cache.close();
    await database.close();
  });

  test('maps products to the cache and back, newest first', () async {
    final repository = CachedRecentScansRepository(cache);
    await repository.record(_product(1));
    await repository.record(_product(2, price: 7.5, stock: null));
    final recents = await repository.load();
    expect(recents.map((p) => p.id), [2, 1]);
    expect(recents.first.price, 7.5);
    expect(recents.first.stockQuantity, isNull);
    expect(recents.last.name, 'Product 1');
    expect(recents.last.barcode, 'BC-1');
    expect(recents.last.unit, 'Units');
    expect(recents.last.stockQuantity, 4);
    expect(recents.last.reference, isEmpty, reason: 'reference is not kept');
  });

  test('the category name is kept; a missing one stays null', () async {
    final repository = CachedRecentScansRepository(cache);
    await repository.record(
      const Product(
        id: 1,
        name: 'Product 1',
        barcode: 'BC-1',
        price: 1,
        stockQuantity: 1,
        category: ' Spices ',
      ),
    );
    await repository.record(_product(2));
    final recents = await repository.load();
    expect(recents.first.category, isNull);
    expect(recents.last.category, 'Spices');
  });

  test('a restarted repository reads the same history', () async {
    await CachedRecentScansRepository(cache).record(_product(1));
    final restarted = EncryptedReadCache(database, sessionSecret: 'repo');
    addTearDown(restarted.close);
    expect((await CachedRecentScansRepository(restarted).load()).single.id, 1);
  });

  test('without a session cache nothing is stored', () async {
    const repository = CachedRecentScansRepository(null);
    await repository.record(_product(1));
    expect(await repository.load(), isEmpty);
  });

  test('storage failures never reach the caller', () async {
    final repository = CachedRecentScansRepository(cache);
    await repository.record(_product(1));
    await database.customStatement('UPDATE product_reads SET payload = ?', [
      'broken',
    ]);
    expect(await repository.load(), isEmpty);
    await repository.record(_product(2));
    expect((await repository.load()).single.id, 2);
    await cache.close();
    await repository.record(_product(3));
    expect(await repository.load(), isEmpty);
  });

  test('the in-memory history has the same ordering and limit', () async {
    final repository = MemoryRecentScansRepository();
    for (var id = 1; id <= EncryptedReadCache.recentScanLimit + 2; id++) {
      await repository.record(_product(id));
    }
    await repository.record(_product(5, price: 1));
    final recents = await repository.load();
    expect(recents, hasLength(EncryptedReadCache.recentScanLimit));
    expect(recents.first.id, 5);
    expect(recents.first.price, 1);
    expect(recents.map((p) => p.id).toSet(), hasLength(recents.length));
  });
}
