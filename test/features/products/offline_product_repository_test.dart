import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_fakes.dart';

void main() {
  test(
    'network fallback revokes writes, recovery restores fresh permissions',
    () async {
      final database = ReadCacheDatabase(NativeDatabase.memory());
      final cache = EncryptedReadCache(
        database,
        sessionSecret: 'fixture-token',
      );
      addTearDown(() async {
        await cache.close();
        await database.close();
      });
      var offline = false;
      var revoked = false;
      var requests = 0;
      var signOuts = 0;
      final server = FakeMobileApiServer();
      FakeReply read(RequestOptions request) {
        requests++;
        if (offline) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        return revoked
            ? FakeReply(401, errorEnvelope('TOKEN_REVOKED'))
            : FakeReply(
                200,
                successEnvelope(
                  v2Product(
                    permissions: productPermissions({
                      'product_update_name': false,
                    }),
                  ),
                ),
              );
      }

      server
        ..on('GET /products/by-barcode/0010101010', read)
        ..on('GET /products/10', read)
        // Writes must never be sent offline.
        ..on('PUT /products/10/price', (r) {
          requests++;
          return fail('Unexpected offline write.');
        });
      final api = fakeProductApi(server);
      final repository = OdooProductDetailsRepository(
        ProductCatalogRemoteDataSource(api, cancelToken: CancelToken()),
        cache: cache,
        onSessionRejected: () async {
          signOuts++;
        },
      );
      final fresh = await repository.load(fixtureProduct.barcode);
      expect(fresh.access.updatePrice, isTrue);
      expect(fresh.access.editName, isFalse);
      expect(fresh.product?.version, '3');
      offline = true;
      final cached = await repository.load(fixtureProduct.barcode);
      expect(cached.product?.name, fixtureProduct.name);
      expect(cached.access.updatePrice, isFalse);
      expect(cached.access.adjustStock, isFalse);
      expect(cached.product?.version, isNull);
      expect(signOuts, 0);
      final lookup = OdooProductRepository(
        ProductRemoteDataSource(api, cancelToken: CancelToken()),
        cache: cache,
        onSessionRejected: () async {
          signOuts++;
        },
      );
      final before = requests;
      expect(
        (await lookup.findByBarcode(fixtureProduct.barcode))?.name,
        fixtureProduct.name,
      );
      await expectLater(
        repository.updatePrice(fresh.product!, ChfPrice.parse('99')),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        repository.adjustStock(fresh.product!, StockCount.parse('5')),
        throwsA(isA<AppFailure>()),
      );
      await repository.load(fixtureProduct.barcode);
      expect(requests, before);
      offline = false;
      cache.connectionChanged(connected: true);
      final recovered = await Future.wait([
        repository.load(fixtureProduct.barcode),
        repository.load(fixtureProduct.barcode),
      ]);
      expect(recovered.every((details) => details.access.updatePrice), isTrue);
      expect(cache.status(fixtureProduct.barcode).phase, ReadSyncPhase.online);
      revoked = true;
      await expectLater(
        repository.load(fixtureProduct.barcode),
        throwsA(isA<AppFailure>()),
      );
      expect(signOuts, 1);
      expect(await cache.read(fixtureProduct.barcode), isNull);
    },
  );
}
