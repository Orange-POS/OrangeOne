import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/home/data/repositories/recent_scans_repositories.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/providers/recent_scans_providers.dart';

import '../../../support/product_fakes.dart';

class _Catalog extends FakeProductRepository {
  final catalog = <String, Product>{};

  @override
  Future<Product?> findByBarcode(String barcode, {bool refresh = false}) async {
    barcodes.add(barcode);
    if (failure != null) throw failure!;
    return catalog[barcode];
  }
}

Product _product(int id, {double price = 10}) => Product(
  id: id,
  name: 'Product $id',
  barcode: 'BC-$id',
  price: price,
  stockQuantity: 3,
  unit: 'Units',
);

void main() {
  late ReadCacheDatabase database;
  late _Catalog products;
  setUp(() {
    database = ReadCacheDatabase(NativeDatabase.memory());
    products = _Catalog();
    for (var id = 1; id <= 7; id++) {
      products.catalog['BC-$id'] = _product(id);
    }
  });
  tearDown(() => database.close());

  ProviderContainer open(EncryptedReadCache? cache) {
    return ProviderContainer.test(
        overrides: [
          productRepositoryProvider.overrideWithValue(products),
          recentScansRepositoryProvider.overrideWithValue(
            CachedRecentScansRepository(cache),
          ),
        ],
      )
      ..listen(productLookupControllerProvider, (_, _) {})
      ..listen(recentScansControllerProvider, (_, _) {});
  }

  Future<List<Product>> recents(ProviderContainer container) async {
    // Recording runs in the background after a lookup.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return await container.read(recentScansControllerProvider.future);
  }

  Future<EncryptedReadCache> newCache(String session) async {
    final cache = EncryptedReadCache(database, sessionSecret: session);
    addTearDown(cache.close);
    return cache;
  }

  test('a found product joins the history, newest first', () async {
    final container = open(await newCache('s1'));
    final lookup = container.read(productLookupControllerProvider.notifier);
    await lookup.scan('BC-1');
    lookup.scanAgain();
    await lookup.scan('BC-2');
    expect((await recents(container)).map((p) => p.barcode), ['BC-2', 'BC-1']);
  });

  test('unknown barcodes and failed lookups are not recorded', () async {
    final container = open(await newCache('s1'));
    final lookup = container.read(productLookupControllerProvider.notifier);
    await lookup.scan('NOPE');
    lookup.scanAgain();
    products.failure = const AppFailure(FailureKind.network, 'Offline');
    await lookup.scan('BC-1');
    lookup.scanAgain();
    await lookup.scan('  ');
    expect(await recents(container), isEmpty);
  });

  test('a rescan moves the product up and refreshes its price', () async {
    final container = open(await newCache('s1'));
    final lookup = container.read(productLookupControllerProvider.notifier);
    await lookup.scan('BC-1');
    lookup.scanAgain();
    await lookup.scan('BC-2');
    lookup.scanAgain();
    products.catalog['BC-1'] = _product(1, price: 55);
    await lookup.scan('BC-1');
    final list = await recents(container);
    expect(list.map((p) => p.barcode), ['BC-1', 'BC-2']);
    expect(list.first.price, 55);
  });

  test('only the five most recent products are kept', () async {
    final container = open(await newCache('s1'));
    final lookup = container.read(productLookupControllerProvider.notifier);
    for (var id = 1; id <= 7; id++) {
      await lookup.scan('BC-$id');
      lookup.scanAgain();
    }
    final list = await recents(container);
    expect(list.map((p) => p.barcode), [
      'BC-7',
      'BC-6',
      'BC-5',
      'BC-4',
      'BC-3',
    ]);
  });

  test('the history survives an app restart', () async {
    final cache = await newCache('s1');
    final first = open(cache);
    await first.read(productLookupControllerProvider.notifier).scan('BC-3');
    await recents(first);
    first.dispose();
    final restarted = open(await newCache('s1'));
    expect((await recents(restarted)).single.barcode, 'BC-3');
  });

  test('another session sees none of it, and keeps its own', () async {
    final first = open(await newCache('s1'));
    await first.read(productLookupControllerProvider.notifier).scan('BC-1');
    await recents(first);

    final other = open(await newCache('s2'));
    expect(await recents(other), isEmpty);
    await other.read(productLookupControllerProvider.notifier).scan('BC-2');
    expect((await recents(other)).single.barcode, 'BC-2');
    expect((await recents(first)).single.barcode, 'BC-1');
  });

  test('ending the session deletes its history', () async {
    final cache = await newCache('s1');
    final container = open(cache);
    await container.read(productLookupControllerProvider.notifier).scan('BC-1');
    await recents(container);
    await cache.close();
    expect(
      await open(await newCache('s1'))
          .read(recentScansControllerProvider.future),
      isEmpty,
    );
  });

  test('without a cache the history is simply empty', () async {
    final container = open(null);
    await container.read(productLookupControllerProvider.notifier).scan('BC-1');
    expect(await recents(container), isEmpty);
  });

  test('a recorded scan never fails the lookup', () async {
    final cache = await newCache('s1');
    final container = open(cache);
    await database.customStatement('DROP TABLE product_reads');
    final lookup = container.read(productLookupControllerProvider.notifier);
    await lookup.scan('BC-1');
    expect(
      container.read(productLookupControllerProvider).requireValue?.product,
      isNotNull,
    );
    // Restore the table so the session can be closed cleanly.
    await database.customStatement(
      'CREATE TABLE product_reads (owner TEXT NOT NULL, code TEXT NOT NULL, '
      'payload TEXT NOT NULL, PRIMARY KEY(owner, code))',
    );
  });
}
