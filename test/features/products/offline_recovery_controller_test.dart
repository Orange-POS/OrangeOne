import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/presentation/providers/price_update_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';

import '../../support/product_details_fakes.dart';

class CountingCreationRepository extends FakeDetailsRepository {
  int preparations = 0;
  @override
  Future<ProductCreationContext> prepareCreation(
    String barcode, {
    bool refresh = false,
  }) {
    preparations++;
    return super.prepareCreation(barcode, refresh: refresh);
  }
}

void main() {
  for (final screen in ['details', 'price', 'edit', 'create']) {
    test('$screen refreshes on both recovery events in one session', () async {
      final database = ReadCacheDatabase(NativeDatabase.memory());
      final cache = EncryptedReadCache(database, sessionSecret: 'test-session');
      final repository = CountingCreationRepository();
      if (screen == 'create') repository.product = null;
      final container = ProviderContainer.test(
        overrides: [
          readCacheProvider.overrideWithValue(cache),
          productDetailsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await cache.close();
        await database.close();
      });
      const code = '0010101010';
      switch (screen) {
        case 'details':
          container.listen(productDetailsControllerProvider(code), (_, _) {});
          await container.read(productDetailsControllerProvider(code).future);
        case 'price':
          container.listen(priceUpdateControllerProvider(code), (_, _) {});
          await container.read(priceUpdateControllerProvider(code).future);
          container
              .read(priceUpdateControllerProvider(code).notifier)
              .changePrice('12');
        case 'edit':
          container.listen(productEditControllerProvider(code), (_, _) {});
          await container.read(productEditControllerProvider(code).future);
        case 'create':
          container.listen(productCreationControllerProvider(code), (_, _) {});
          await container.read(productCreationControllerProvider(code).future);
          container
              .read(productCreationControllerProvider(code).notifier)
              .edit(name: 'Draft', price: '12');
      }
      final events = <int>[];
      container.listen(readCacheRecoveryProvider, (_, next) {
        if (next.hasValue) events.add(next.requireValue);
      });
      await container.pump();
      for (var cycle = 1; cycle <= 2; cycle++) {
        cache.connectionChanged(connected: false);
        await container.pump();
        cache.connectionChanged(connected: true);
        await container.pump();
        expect(events, List.generate(cycle, (index) => index + 1));
        expect(
          screen == 'create' ? repository.preparations : repository.loads,
          cycle + 1,
        );
      }
      if (screen == 'price') {
        expect(
          container
              .read(priceUpdateControllerProvider(code))
              .requireValue
              .draft,
          '12',
        );
      }
      if (screen == 'create') {
        expect(
          container
              .read(productCreationControllerProvider(code))
              .requireValue
              .name,
          'Draft',
        );
      }
    });
  }
}
