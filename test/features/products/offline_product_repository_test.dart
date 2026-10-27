import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';

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
      final dio = Dio();
      addTearDown(() async {
        dio.close(force: true);
        await cache.close();
        await database.close();
      });
      var offline = false;
      var revoked = false;
      var requests = 0;
      var signOuts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests++;
            if (offline) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'jsonrpc': '2.0',
                  'id': (request.data as Map)['id'],
                  'result': revoked
                      ? {'ok': false, 'error': 'Token is not active.'}
                      : request.path.endsWith('/token/check')
                      ? {
                          'ok': true,
                          'scopes':
                              'product:read product:name_update '
                              'product:price_update',
                        }
                      : {'ok': true, 'product': productJson()},
                },
              ),
            );
          },
        ),
      );
      final repository = OdooProductDetailsRepository(
        ProductDetailsRemoteDataSource(
          JsonRpcClient(
            dio,
            const ApiConfiguration(
              baseUrl: 'https://unused.test',
              environment: AppEnvironment.development,
            ),
          ),
          origin: Uri.parse('https://pos.test'),
          token: () async => 'fixture-token',
          cancelToken: CancelToken(),
        ),
        cache: cache,
        onSessionRejected: () async {
          signOuts++;
        },
      );
      final fresh = await repository.load(fixtureProduct.barcode);
      expect(fresh.access.updatePrice, isTrue);
      offline = true;
      final cached = await repository.load(fixtureProduct.barcode);
      expect(cached.product?.name, fixtureProduct.name);
      expect(cached.access.updatePrice, isFalse);
      expect(cached.access.editName, isFalse);
      expect(signOuts, 0);
      final lookup = OdooProductRepository(
        ProductRemoteDataSource(
          JsonRpcClient(
            dio,
            const ApiConfiguration(
              baseUrl: 'https://unused.test',
              environment: AppEnvironment.development,
            ),
          ),
          origin: Uri.parse('https://pos.test'),
          accessToken: () async => 'fixture-token',
          cancelToken: CancelToken(),
        ),
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
        repository.updatePrice(10, 99),
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
