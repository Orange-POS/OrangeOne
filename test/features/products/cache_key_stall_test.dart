import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_details_fakes.dart';

// P1 (review of #63): a cache-key read from secure storage that never
// completes must neither keep a verified lookup loading nor let a write go
// out before the cache was invalidated.
void main() {
  const code = '0010101010';
  const deadline = Duration(milliseconds: 50);
  late ReadCacheDatabase database;
  late Completer<String> keyRead;
  late int keyReads;
  late EncryptedReadCache cache;
  late OdooProductDetailsRepository repository;
  late List<String> requests;

  setUp(() {
    database = ReadCacheDatabase(NativeDatabase.memory());
    keyRead = Completer<String>();
    keyReads = 0;
    cache = EncryptedReadCache(
      database,
      sessionSecret: 'synthetic-session',
      keySecret: () {
        keyReads++;
        return keyRead.future;
      },
      keySecretTimeout: deadline,
    );
    requests = [];
    FakeReply read(RequestOptions request) {
      requests.add('${request.method} ${request.uri.path}');
      return FakeReply(
        200,
        successEnvelope({...v2Product(), 'permissions': productPermissions()}),
      );
    }

    final server = FakeMobileApiServer()
      ..on('GET /products/by-barcode/$code', read)
      ..on('GET /products/10', read)
      ..on('PUT /products/10/price', read);
    repository = OdooProductDetailsRepository(
      ProductCatalogRemoteDataSource(
        fakeProductApi(server),
        cancelToken: CancelToken(),
      ),
      cache: cache,
      onSessionRejected: () async {},
    );
    addTearDown(() async {
      if (!keyRead.isCompleted) keyRead.complete('released');
      await cache.close();
      await database.close();
    });
  });

  test('a stalled key read returns the server-verified product', () async {
    final details = await repository
        .load(code)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('The lookup waited for the cache key.'),
        );
    expect(details.product?.name, v2Product()['name']);
    expect(details.access.updatePrice, isTrue);
    expect(cache.offline, isFalse);
    // Not cached, and nothing stale may be served for it.
    expect(cache.status(code).phase, ReadSyncPhase.failed);
    expect(
      await database.customSelect('SELECT * FROM product_reads').get(),
      isEmpty,
    );
    expect(await cache.read(code), isNull);
  });

  test('a stalled key read before a write sends nothing', () async {
    await repository.load(code);
    requests.clear();
    await expectLater(
      repository
          .updatePrice(detailsFixture, ChfPrice.parse('12'))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('The write waited for the cache key.'),
          ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          FailureKind.storage,
        ),
      ),
    );
    expect(
      requests.where((request) => request.startsWith('PUT')),
      isEmpty,
      reason: 'no write without invalidation',
    );
  });

  test('the key read is tried again once storage answers', () async {
    await repository.load(code);
    final before = keyReads;
    keyRead.complete('stored-secret');
    final details = await repository.load(code);
    expect(details.product?.name, v2Product()['name']);
    expect(keyReads, greaterThan(before));
    expect(cache.status(code).phase, ReadSyncPhase.online);
    expect((await cache.read(code))?['name'], v2Product()['name']);
  });
}
