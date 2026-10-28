import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/network/product_payload.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/data/repositories/product_cache_synchronizer.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';

const _feed = 'GET /products/changes';

Map<String, dynamic> _page({
  List<Map<String, dynamic>> changed = const [],
  List<int> removed = const [],
  String next = 'next-1',
  bool more = false,
}) => {
  'changed': changed,
  'removed_ids': removed,
  'next_since': next,
  'has_more': more,
};

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  late FakeMobileApiServer server;
  late ProductCatalogRemoteDataSource catalog;
  late ProductCacheSynchronizer sync;
  late DateTime now;
  var rejected = 0;
  setUp(() async {
    database = ReadCacheDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 27, 9);
    cache = EncryptedReadCache(database, sessionSecret: 'sync', now: () => now);
    server = FakeMobileApiServer();
    catalog = ProductCatalogRemoteDataSource(
      fakeProductApi(server),
      cancelToken: CancelToken(),
    );
    rejected = 0;
    sync = ProductCacheSynchronizer(
      catalog,
      cache,
      onSessionRejected: () async => rejected++,
    );
    await cache.load(
      '0010101010',
      () async => ProductPayload.productRecord({
        ...v2Product(),
        'updated_at': '2026-10-27T07:00:00Z',
      }),
    );
  });
  tearDown(() async {
    await cache.close();
    await database.close();
  });

  Future<double?> cachedPrice() async =>
      (await cache.read('0010101010'))?['price'] as double?;

  test('pages through changes and saves each position', () async {
    final pages = [
      _page(next: 'p1', more: true),
      _page(
        changed: [
          {...v2Product(price: '120.00'), 'updated_at': '2026-10-27T08:00:00Z'},
        ],
        next: 'p2',
      ),
    ];
    server.on(_feed, (_) => FakeReply(200, successEnvelope(pages.removeAt(0))));
    await sync.sync();
    final sinces = [
      for (final r in server.called(_feed)) r.uri.queryParameters['since'],
    ];
    expect(sinces, ['2026-10-27T08:55:00Z', 'p1']);
    expect(server.called(_feed).first.uri.queryParameters['limit'], '100');
    expect(await cachedPrice(), 120);
    expect((await cache.syncState())?.since, 'p2');
  });

  test('removed products leave the offline cache', () async {
    server.on(
      _feed,
      (_) => FakeReply(200, successEnvelope(_page(removed: [10]))),
    );
    await sync.sync();
    expect(await cache.read('0010101010'), isNull);
  });

  test(
    'an interrupted sync keeps data and resumes from its position',
    () async {
      var calls = 0;
      server.on(_feed, (r) {
        calls++;
        if (calls == 2) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        return FakeReply(
          200,
          successEnvelope(_page(next: 'p$calls', more: true)),
        );
      });
      await sync.sync();
      expect(calls, 2);
      expect(await cachedPrice(), 100);
      expect((await cache.syncState())?.since, 'p1');
      await sync.sync();
      expect(server.called(_feed)[2].uri.queryParameters['since'], 'p1');
    },
  );

  test('a malformed page changes nothing', () async {
    server.on(
      _feed,
      (_) => FakeReply(
        200,
        successEnvelope({
          ..._page(removed: [10]),
          'has_more': 'yes',
        }),
      ),
    );
    await sync.sync();
    expect(await cachedPrice(), 100);
    expect(
      (await cache.syncState())?.since,
      '2026-10-27T08:55:00Z',
      reason: 'position unchanged',
    );
  });

  for (final (label, status, code) in [
    ('an expired position', 410, 'SYNC_TOKEN_EXPIRED'),
    ('lost read access', 403, 'PERMISSION_DENIED'),
  ]) {
    test('$label drops the session snapshots', () async {
      server.on(_feed, (_) => FakeReply(status, errorEnvelope(code)));
      await sync.sync();
      expect(await cache.read('0010101010'), isNull);
      expect(await cache.syncState(), isNull);
    });
  }

  for (final code in ['TOKEN_REVOKED', 'TOKEN_INVALID', 'AUTH_REQUIRED']) {
    test('$code is reported once and stops the sync', () async {
      server.on(_feed, (_) => FakeReply(401, errorEnvelope(code)));
      await sync.sync();
      expect(rejected, 1);
      expect(server.called(_feed), hasLength(1), reason: 'no retry or replay');
    });
  }

  test('outages and a disabled feed are not session rejections', () async {
    server.on(_feed, (_) => FakeReply(404, errorEnvelope('NOT_FOUND')));
    await sync.sync();
    server.on(_feed, (_) => FakeReply(503, errorEnvelope('MAINTENANCE')));
    await sync.sync();
    expect(rejected, 0);
  });

  test('a disabled feed or outage keeps the cache', () async {
    server.on(_feed, (_) => FakeReply(404, errorEnvelope('NOT_FOUND')));
    await sync.sync();
    server.on(_feed, (_) => FakeReply(503, errorEnvelope('MAINTENANCE')));
    await sync.sync();
    expect(await cachedPrice(), 100);
  });

  test('runs are bounded and concurrent requests share one', () async {
    server.on(
      _feed,
      (_) => FakeReply(200, successEnvelope(_page(next: 'loop', more: true))),
    );
    await Future.wait([sync.sync(), sync.sync()]);
    expect(server.called(_feed), hasLength(sync.maxPages));
  });

  test('nothing cached means no feed request', () async {
    await cache.resetSync();
    await sync.sync();
    expect(server.called(_feed), isEmpty);
  });

  test('a confirmed write refreshes the cached snapshot', () async {
    server
      ..on(
        'GET /products/by-barcode/0010101010',
        (_) => FakeReply(200, successEnvelope(v2Product())),
      )
      ..on(
        'PUT /products/10/price',
        (_) => FakeReply(
          200,
          successEnvelope(v2Product(price: '130.00', version: '4')),
        ),
      );
    final repository = OdooProductDetailsRepository(
      catalog,
      cache: cache,
      onSessionRejected: () async {},
    );
    final product = (await repository.load('0010101010')).product!;
    await repository.updatePrice(product, ChfPrice.parse('130'));
    expect(await cachedPrice(), 130);

    // Offline afterwards: the confirmed data is served read-only.
    cache.connectionChanged(connected: false);
    final offline = await repository.load('0010101010');
    expect(offline.product?.price, 130);
    expect(offline.product?.version, isNull);
    expect(offline.access.updatePrice, isFalse);
    await expectLater(
      repository.updatePrice(offline.product!, ChfPrice.parse('140')),
      throwsA(anything),
    );
    expect(server.called('PUT /products/10/price'), hasLength(1));
  });
}
