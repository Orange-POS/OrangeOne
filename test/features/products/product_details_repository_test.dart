import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_fakes.dart';

void main() {
  late Dio dio;
  late OdooProductDetailsRepository repo;
  late List<RequestOptions> requests;
  late Map<String, dynamic> result;
  late FakeMobileApiServer server;
  late int signOuts;
  const scan = 'GET /products/by-barcode/0010101010';
  setUp(() {
    dio = Dio();
    requests = [];
    signOuts = 0;
    result = {'ok': true, 'product': productJson()};
    server = FakeMobileApiServer()
      ..on(scan, (_) => FakeReply(200, successEnvelope(v2Product())));
    repo = OdooProductDetailsRepository(
      ProductDetailsRemoteDataSource(
        JsonRpcClient(
          dio,
          const ApiConfiguration(
            baseUrl: 'https://unused.test',
            environment: AppEnvironment.production,
          ),
        ),
        origin: Uri.parse('http://192.168.1.3:8080'),
        token: () async => 'fixture',
        cancelToken: CancelToken(),
      ),
      catalog: ProductCatalogRemoteDataSource(
        fakeProductApi(server),
        cancelToken: CancelToken(),
      ),
      onSessionRejected: () async {
        signOuts++;
      },
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'jsonrpc': '2.0',
                'id': (request.data as Map)['id'],
                'result': result,
              },
            ),
          );
        },
      ),
    );
  });
  tearDown(() => dio.close(force: true));
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
  ]) {
    test('first $type during an uncached read logs out', () async {
      server.on(scan, (r) => throw DioException(requestOptions: r, type: type));
      await expectLater(repo.load('0010101010'), throwsA(isA<AppFailure>()));
      expect(signOuts, 1);
      expect(server.requests, hasLength(1));
    });
  }
  test(
    'combined edit uses confirmed fields and maps acknowledgement',
    () async {
      result = {
        'ok': true,
        'product': productJson()
          ..['name'] = 'Updated'
          ..['taxes'] = [
            {'id': 7, 'name': 'VAT', 'amount': 15, 'amount_type': 'percent'},
          ],
      };
      final updated = await repo.updateInformation(10, 'Updated', taxIds: [7]);
      expect(updated.name, 'Updated');
      expect(updated.taxIds, [7]);
      expect(updated.taxes, ['VAT (15%)']);
      expect(requests.single.path, endsWith('/products/update'));
      expect((requests.single.data as Map)['params'], {
        'product_id': 10,
        'name': 'Updated',
        'tax_ids': [7],
      });
    },
  );
  test(
    'omits taxes for name-only edit and sends [] for explicit no-tax',
    () async {
      await repo.updateInformation(10, 'Name');
      expect((requests.last.data as Map)['params'], {
        'product_id': 10,
        'name': 'Name',
      });
      await repo.updateInformation(10, 'Name', taxIds: []);
      expect(
        ((requests.last.data as Map)['params'] as Map)['tax_ids'],
        isEmpty,
      );
    },
  );
  test('maps company tax catalogue and rejects malformed identities', () async {
    result = {
      'ok': true,
      'default_tax_ids': [7],
      'taxes': [
        {'id': 7, 'name': 'VAT', 'amount': 15, 'amount_type': 'percent'},
        {'id': 8, 'name': 'Fixed levy', 'amount': 2, 'amount_type': 'fixed'},
      ],
    };
    final taxes = await repo.loadTaxes();
    expect(taxes.map((tax) => tax.label), ['VAT (15%)', 'Fixed levy']);
    expect(requests.single.path, endsWith('/products/references'));
    result = {
      'ok': true,
      'taxes': [
        {'id': -1},
      ],
    };
    await expectLater(repo.loadTaxes(), throwsA(isA<AppFailure>()));
  });
  test(
    'malformed combined-save acknowledgement never reports success',
    () async {
      result = {'ok': true};
      await expectLater(
        repo.updateInformation(10, 'Name'),
        throwsA(isA<AppFailure>()),
      );
      expect(requests.length, 1);
    },
  );
  test('reads v2 details and permissions from the session API base', () async {
    server.on(
      scan,
      (_) => FakeReply(
        200,
        successEnvelope(
          v2Product(
            permissions: productPermissions({
              'product_update_price': false,
              'stock_adjust': false,
            }),
          ),
        ),
      ),
    );
    final value = await repo.load('0010101010');
    final product = value.product!;
    expect(product.name, fixtureProduct.name);
    expect(product.price, 100);
    expect(product.currency, 'CHF');
    expect(product.stock, 48);
    expect(product.unit, 'Units');
    expect(product.reference, 'MASALA');
    expect(product.taxes, ['VAT (8.1%)']);
    expect(product.taxIds, [7]);
    expect(product.category?.name, 'Spices');
    expect(product.description, 'The Key to Crispy, Flavorful Fish');
    expect(product.version, '3');
    expect(product.stockAdjustable, isTrue);
    expect(value.access.editName, isTrue);
    expect(value.access.updateTaxes, isTrue);
    expect(value.access.createProduct, isTrue);
    expect(value.access.updatePrice, isFalse);
    expect(value.access.adjustStock, isFalse);
    final request = server.requests.single;
    expect(
      request.uri.toString(),
      '$testApiBase/products/by-barcode/0010101010',
    );
    expect(request.headers['Authorization'], 'Bearer oa_fixture');
    expect(requests, isEmpty);
  });
  test('untracked stock is unavailable, never zero', () async {
    server.on(
      scan,
      (_) => FakeReply(200, successEnvelope(v2Product(quantity: null))),
    );
    final product = (await repo.load('0010101010')).product!;
    expect(product.stock, isNull);
    expect(product.stockAdjustable, isFalse);
  });
  test('a repeated read is conditional; 304 keeps previous details', () async {
    server
      ..on(
        scan,
        (_) => FakeReply(200, successEnvelope(v2Product()), {'etag': '"e1"'}),
      )
      ..on('GET /products/10', (_) => const FakeReply(304));
    final first = await repo.load('0010101010');
    final second = await repo.load('0010101010');
    expect(server.called(scan), hasLength(1));
    final refresh = server.called('GET /products/10').single;
    expect(refresh.headers['If-None-Match'], '"e1"');
    expect(second.product?.version, first.product?.version);
    expect(second.product?.price, 100);
    expect(second.access.editName, isTrue);
  });
  test('a changed representation replaces data, version and access', () async {
    server
      ..on(
        scan,
        (_) => FakeReply(200, successEnvelope(v2Product()), {'etag': '"e1"'}),
      )
      ..on(
        'GET /products/10',
        (_) => FakeReply(
          200,
          successEnvelope(
            v2Product(
              price: '125.50',
              version: '4',
              permissions: productPermissions({'product_update_name': false}),
            ),
          ),
          {'etag': '"e2"'},
        ),
      );
    await repo.load('0010101010');
    final refreshed = await repo.load('0010101010');
    expect(refreshed.product?.price, 125.5);
    expect(refreshed.product?.version, '4');
    expect(refreshed.access.editName, isFalse);
    await repo.load('0010101010');
    expect(
      server.called('GET /products/10').last.headers['If-None-Match'],
      '"e2"',
    );
  });
  test('removed or re-barcoded products are looked up again', () async {
    server
      ..on(
        scan,
        (_) => FakeReply(200, successEnvelope(v2Product()), {'etag': '"e1"'}),
      )
      ..on(
        'GET /products/10',
        (_) => FakeReply(404, errorEnvelope('PRODUCT_NOT_FOUND')),
      );
    await repo.load('0010101010');
    server.on(
      scan,
      (_) => FakeReply(200, successEnvelope(v2Product(id: 12, version: '1'))),
    );
    expect((await repo.load('0010101010')).product?.id, 12);

    server
      ..on(
        'GET /products/12',
        (_) => FakeReply(200, successEnvelope(v2Product(id: 12, barcode: 'x'))),
      )
      ..on(scan, (_) => FakeReply(404, errorEnvelope('PRODUCT_NOT_FOUND')))
      ..on(
        'GET /auth/session',
        (_) =>
            FakeReply(200, successEnvelope(sessionData(productPermissions()))),
      );
    final missing = await repo.load('0010101010');
    expect(missing.product, isNull);
    expect(missing.access.createProduct, isTrue);
    expect(server.called(scan), hasLength(3));
  });
  test('invalid barcodes are rejected before any request', () async {
    await expectLater(
      repo.load('has space'),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.validation),
      ),
    );
    expect(server.requests, isEmpty);
  });
  test('a forbidden product keeps the session', () async {
    server.on(scan, (_) => FakeReply(403, errorEnvelope('COMPANY_MISMATCH')));
    await expectLater(
      repo.load('0010101010'),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.forbidden),
      ),
    );
    expect(signOuts, 0);
  });
  test('search maps a page and forwards its filters and cursor', () async {
    server.on(
      'GET /products',
      (_) => const FakeReply(200, {
        'data': [
          {
            'id': 10,
            'name': 'Aachi Fish Fry Masala',
            'barcode': '0010101010',
            'list_price': {'amount': '100.00', 'currency': 'CHF'},
            'stock_quantity': '48.000',
          },
          {
            'id': 11,
            'name': 'Service',
            'barcode': null,
            'list_price': {'amount': '5.50', 'currency': 'CHF'},
            'stock_quantity': null,
          },
        ],
        'meta': {'request_id': 'request-1', 'next_cursor': 'c2'},
      }),
    );
    final page = await repo.searchProducts(
      query: 'masala',
      categoryId: 4,
      cursor: 'c1',
      limit: 2,
    );
    expect(page.items.map((item) => item.id), [10, 11]);
    expect(page.items.first.stock, 48);
    expect(page.items.last.barcode, isNull);
    expect(page.items.last.stock, isNull);
    expect(page.items.last.price, 5.5);
    expect(page.nextCursor, 'c2');
    expect(server.requests.single.uri.queryParameters, {
      'q': 'masala',
      'category_id': '4',
      'cursor': 'c1',
      'limit': '2',
    });
  });
  test(
    'writes use designated name and price endpoints without retries',
    () async {
      await repo.updateName(10, 'New');
      await repo.updatePrice(10, 12.50);
      expect(requests.length, 2);
      expect(requests.first.path, endsWith('/products/name/update'));
      expect((requests.last.data as Map)['params'], {
        'product_id': 10,
        'price': 12.50,
      });
    },
  );
  test(
    'missing products are empty; malformed matches are protocol errors',
    () async {
      server
        ..on(scan, (_) => FakeReply(404, errorEnvelope('PRODUCT_NOT_FOUND')))
        ..on(
          'GET /auth/session',
          (_) => FakeReply(
            200,
            successEnvelope(
              sessionData(productPermissions({'product_create': false})),
            ),
          ),
        );
      final missing = await repo.load('0010101010');
      expect(missing.product, isNull);
      expect(missing.access.createProduct, isFalse);
      for (final payload in [
        <Object>[],
        {
          ...v2Product(),
          'list_price': {'amount': 1, 'currency': 'CHF'},
        },
        {
          ...v2Product(),
          'permissions': {'product_read': 'yes'},
        },
        v2Product(barcode: 'other'),
      ]) {
        server.on(scan, (_) => FakeReply(200, successEnvelope(payload)));
        await expectLater(
          repo.load('0010101010'),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.protocol,
            ),
          ),
        );
      }
    },
  );
  test('permission denial keeps session; expired token clears it', () async {
    result = {'ok': false, 'error': 'Token does not have required permission.'};
    await expectLater(
      repo.updatePrice(10, 2),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.forbidden),
      ),
    );
    expect(signOuts, 0);
    server.on(scan, (_) => FakeReply(401, errorEnvelope('TOKEN_REVOKED')));
    await expectLater(repo.load('0010101010'), throwsA(isA<AppFailure>()));
    expect(signOuts, 1);
  });

  test('price update maps the acknowledged server product', () async {
    result = {
      'ok': true,
      'product': {...productJson(), 'price': 125.25},
    };
    final updated = await repo.updatePrice(10, 125.25);
    expect(updated.price, 125.25);
    expect(updated.barcode, fixtureProduct.barcode);
    expect(requests.single.headers['Authorization'], 'Bearer fixture');
  });

  for (final product in [
    null,
    <Object>[],
    {'id': 10},
    {...productJson(), 'id': 11},
    {...productJson(), 'barcode': ''},
    {...productJson(), 'price': double.nan},
  ]) {
    test(
      'malformed price acknowledgment cannot report success ($product)',
      () async {
        result = {'ok': true, 'product': product};
        await expectLater(
          repo.updatePrice(10, 125),
          throwsA(
            isA<AppFailure>().having(
              (error) => error.kind,
              'kind',
              FailureKind.protocol,
            ),
          ),
        );
        expect(requests.length, 1);
      },
    );
  }
}
