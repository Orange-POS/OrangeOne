import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';

Matcher _kind(FailureKind kind) =>
    throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', kind));

void main() {
  const scan = 'GET /products/by-barcode/0010101010';
  const create = 'POST /products';
  late FakeMobileApiServer server;
  late OdooProductDetailsRepository repository;
  late Map<String, bool> permissions;
  Map<String, dynamic>? found;
  FakeReply created(RequestOptions _) => FakeReply(
    201,
    successEnvelope({
      ...v2Product(name: 'New', version: '1'),
      'taxes': <Object>[],
    }),
    {'location': '/api/orangeone/mobile/v1/products/10'},
  );

  setUp(() {
    permissions = productPermissions();
    found = null;
    server = FakeMobileApiServer()
      ..on(
        scan,
        (_) => found == null
            ? FakeReply(404, errorEnvelope('PRODUCT_NOT_FOUND'))
            : FakeReply(200, successEnvelope(found)),
      )
      ..on(
        'GET /auth/session',
        (_) => FakeReply(200, successEnvelope(sessionData(permissions))),
      )
      ..on(
        'GET /taxes',
        (_) => FakeReply(
          200,
          successEnvelope({
            'taxes': [
              {
                'id': 1,
                'name': 'VAT',
                'amount': '15',
                'amount_type': 'percent',
                'price_include': false,
              },
            ],
            'default_tax_ids': [1],
          }),
        ),
      )
      ..on(create, created);
    repository = OdooProductDetailsRepository(
      ProductCatalogRemoteDataSource(
        fakeProductApi(server),
        cancelToken: CancelToken(),
      ),
      onSessionRejected: () async {},
    );
  });
  NewProduct draft({List<int> taxIds = const []}) => NewProduct(
    barcode: '0010101010',
    name: 'New',
    price: ChfPrice.parse('100'),
    taxIds: taxIds,
  );

  test('rechecks permission and creates with an explicit No Tax', () async {
    final product = await repository.createProduct(draft());
    expect(product.id, 10);
    expect(product.taxIds, isEmpty);
    expect(product.version, '1');
    expect(server.requests.map((r) => '${r.method} ${r.uri.path}'), [
      'GET /api/orangeone/mobile/v1/products/by-barcode/0010101010',
      'GET /api/orangeone/mobile/v1/auth/session',
      'GET /api/orangeone/mobile/v1/taxes',
      'POST /api/orangeone/mobile/v1/products',
    ]);
    final request = server.called(create).single;
    expect(requestBody(request), {
      'barcode': '0010101010',
      'name': 'New',
      'list_price': '100.00',
      'tax_ids': <int>[],
    });
    expect(request.headers['Idempotency-Key'], isNotEmpty);
    expect(request.headers.containsKey('If-Match'), isFalse);
  });

  test(
    'cached creation keeps the online preflight; offline is blocked',
    () async {
      final db = ReadCacheDatabase(NativeDatabase.memory());
      final cache = EncryptedReadCache(db, sessionSecret: 'creation-fixture');
      addTearDown(() async {
        await cache.close();
        await db.close();
      });
      final cached = OdooProductDetailsRepository(
        repository.catalog,
        cache: cache,
        onSessionRejected: () async {},
      );
      expect((await cached.createProduct(draft(taxIds: [1]))).id, 10);
      expect(requestBody(server.called(create).single)['tax_ids'], [1]);
      expect(server.called('GET /auth/session'), hasLength(1));

      cache.connectionChanged(connected: false);
      await expectLater(
        cached.createProduct(draft()),
        throwsA(isA<AppFailure>()),
      );
      expect(server.called(create), hasLength(1));
    },
  );

  for (final missing in [
    'product_create',
    'product_update_price',
    'product_read',
  ]) {
    test('missing $missing never sends a create', () async {
      permissions[missing] = false;
      expect(
        (await repository.prepareCreation('0010101010')).canCreate,
        isFalse,
      );
      await expectLater(
        repository.createProduct(draft()),
        _kind(FailureKind.forbidden),
      );
      expect(server.called(create), isEmpty);
    });
  }

  test('an existing product is a conflict without any write', () async {
    found = v2Product();
    await expectLater(
      repository.createProduct(draft()),
      _kind(FailureKind.conflict),
    );
    expect(server.called(create), isEmpty);
  });

  test('an unavailable tax option never sends a create', () async {
    await expectLater(
      repository.createProduct(draft(taxIds: [99])),
      _kind(FailureKind.validation),
    );
    expect(server.called(create), isEmpty);
  });

  test('a server barcode conflict is typed and never retried', () async {
    server.on(create, (_) => FakeReply(409, errorEnvelope('BARCODE_EXISTS')));
    await expectLater(
      repository.createProduct(draft()),
      _kind(FailureKind.conflict),
    );
    expect(server.called(create), hasLength(1));
  });

  test('retrying an uncertain creation reuses its idempotency key', () async {
    server.on(
      create,
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      repository.createProduct(draft()),
      _kind(FailureKind.network),
    );
    // The server replays the stored creation for the same key.
    server.on(create, created);
    await repository.createProduct(draft());
    final keys = [
      for (final request in server.called(create))
        request.headers['Idempotency-Key'],
    ];
    expect(keys, hasLength(2));
    expect(keys[1], keys[0]);

    // Once created, the preflight finds the product: no further write.
    server.on(
      'GET /products/10',
      (_) => FakeReply(200, successEnvelope(v2Product(name: 'New'))),
    );
    await expectLater(
      repository.createProduct(draft()),
      _kind(FailureKind.conflict),
    );
    expect(server.called(create), hasLength(2));
  });

  test('a malformed acknowledgement is never reported as created', () async {
    server.on(
      create,
      (_) => FakeReply(201, successEnvelope(v2Product(barcode: 'other'))),
    );
    await expectLater(
      repository.createProduct(draft()),
      _kind(FailureKind.protocol),
    );
  });
}
