import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_fakes.dart';

Matcher _kind(FailureKind kind) =>
    throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', kind));

void main() {
  late OdooProductDetailsRepository repo;
  late FakeMobileApiServer server;
  late int signOuts;
  const scan = 'GET /products/by-barcode/0010101010';
  const patch = 'PATCH /products/10';
  const price = 'PUT /products/10/price';
  setUp(() {
    signOuts = 0;
    server = FakeMobileApiServer()
      ..on(scan, (_) => FakeReply(200, successEnvelope(v2Product())))
      ..on(
        patch,
        (r) => FakeReply(
          200,
          successEnvelope({
            ...v2Product(version: '4'),
            if (requestBody(r)['name'] case final String name) 'name': name,
          }),
        ),
      )
      ..on(
        price,
        (r) => FakeReply(
          200,
          successEnvelope(
            v2Product(
              price: requestBody(r)['list_price'] as String,
              version: '4',
            ),
          ),
        ),
      );
    repo = OdooProductDetailsRepository(
      ProductCatalogRemoteDataSource(
        fakeProductApi(server),
        cancelToken: CancelToken(),
      ),
      onSessionRejected: () async {
        signOuts++;
      },
    );
  });

  Future<ProductDetails> loaded() async =>
      (await repo.load('0010101010')).product!;
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

  test('price update sends the decimal string, version and a key', () async {
    final product = await loaded();
    final updated = await repo.updatePrice(product, ChfPrice.parse('125,5'));

    expect(updated.price, 125.5);
    expect(updated.version, '4');
    final request = server.called(price).single;
    expect(requestBody(request), {'list_price': '125.50'});
    expect(request.headers['If-Match'], '"3"');
    expect(request.headers['Idempotency-Key'], matches(_uuid));
    expect(request.headers['Authorization'], 'Bearer oa_fixture');
  });

  test('If-Match uses the JSON version, never the ETag', () async {
    server.on(
      scan,
      (_) => FakeReply(200, successEnvelope(v2Product()), {'etag': '"e1"'}),
    );
    await repo.updatePrice(await loaded(), ChfPrice.parse('1'));
    expect(server.called(price).single.headers['If-Match'], '"3"');
  });

  test('PATCH sends only the given fields', () async {
    final product = await loaded();
    final updated = await repo.updateInformation(
      product,
      name: 'Updated',
      taxIds: [7],
      category: const CategoryChange(null),
    );
    expect(updated.name, 'Updated');
    expect(requestBody(server.called(patch).single), {
      'name': 'Updated',
      'tax_ids': [7],
      'category_id': null,
    });

    await repo.updateInformation(product, taxIds: const []);
    expect(requestBody(server.called(patch).last), {'tax_ids': <int>[]});
    await repo.updateInformation(product, category: const CategoryChange(4));
    expect(requestBody(server.called(patch).last), {'category_id': 4});
    expect(() => repo.updateInformation(product), throwsFormatException);
  });

  test('a new write gets a new key; an uncertain one reuses it', () async {
    final product = await loaded();
    await repo.updatePrice(product, ChfPrice.parse('12'));
    await repo.updatePrice(product, ChfPrice.parse('12'));
    final keys = [
      for (final request in server.called(price))
        request.headers['Idempotency-Key'],
    ];
    expect(keys.toSet(), hasLength(2));

    server.on(
      price,
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      repo.updatePrice(product, ChfPrice.parse('13')),
      _kind(FailureKind.network),
    );
    server.on(
      price,
      (_) => FakeReply(200, successEnvelope(v2Product(price: '13.00'))),
    );
    await repo.updatePrice(product, ChfPrice.parse('13'));
    final retried = server.called(price).skip(2).toList();
    expect(
      retried.last.headers['Idempotency-Key'],
      retried.first.headers['Idempotency-Key'],
    );

    // A different operation after the uncertain one never reuses its key.
    await repo.updatePrice(product, ChfPrice.parse('14'));
    expect(
      server.called(price).last.headers['Idempotency-Key'],
      isNot(retried.first.headers['Idempotency-Key']),
    );
  });

  test('a stale version is a conflict and nothing is retried', () async {
    final product = await loaded();
    server.on(price, (_) => FakeReply(412, errorEnvelope('VERSION_CONFLICT')));
    await expectLater(
      repo.updatePrice(product, ChfPrice.parse('2')),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.kind, 'kind', FailureKind.conflict)
            .having((e) => e.message, 'message', contains('another device')),
      ),
    );
    expect(server.called(price), hasLength(1));
    expect(signOuts, 0);
    // The next read is unconditional, so it sees the server's latest data.
    await repo.load('0010101010');
    expect(server.called(scan), hasLength(2));
  });

  test('offline cached details cannot be written', () async {
    const offline = ProductDetails(
      id: 10,
      name: 'Cached',
      barcode: '0010101010',
      price: 1,
      stock: null,
    );
    await expectLater(
      repo.updatePrice(offline, ChfPrice.parse('2')),
      _kind(FailureKind.network),
    );
    expect(server.called(price), isEmpty);
  });

  test('permission denial keeps the session; rejection clears it', () async {
    final product = await loaded();
    server.on(price, (_) => FakeReply(403, errorEnvelope('PERMISSION_DENIED')));
    await expectLater(
      repo.updatePrice(product, ChfPrice.parse('2')),
      _kind(FailureKind.forbidden),
    );
    expect(signOuts, 0);
    server.on(patch, (_) => FakeReply(401, errorEnvelope('TOKEN_REVOKED')));
    await expectLater(
      repo.updateInformation(product, name: 'X'),
      _kind(FailureKind.unauthenticated),
    );
    expect(signOuts, 1);
  });

  test('validation errors keep their field details', () async {
    final product = await loaded();
    server.on(
      patch,
      (_) => const FakeReply(400, {
        'error': {
          'code': 'VALIDATION_FAILED',
          'message': 'Check the product name.',
          'details': [
            {'field': 'name', 'code': 'too_long'},
          ],
        },
        'meta': {'request_id': 'request-1'},
      }),
    );
    await expectLater(
      repo.updateInformation(product, name: 'X'),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.kind, 'kind', FailureKind.validation)
            .having((e) => e.fieldErrors.single.field, 'field', 'name'),
      ),
    );
  });

  for (final payload in [
    null,
    <Object>[],
    v2Product(id: 11, barcode: 'other'),
    {...v2Product(), 'version': null},
  ]) {
    test(
      'malformed write acknowledgement is never success ($payload)',
      () async {
        final product = await loaded();
        server.on(price, (_) => FakeReply(200, successEnvelope(payload)));
        await expectLater(
          repo.updatePrice(product, ChfPrice.parse('2')),
          _kind(FailureKind.protocol),
        );
        expect(server.called(price), hasLength(1));
      },
    );
  }

  test('tax and category references map the v2 lists', () async {
    server
      ..on(
        'GET /taxes',
        (_) => FakeReply(
          200,
          successEnvelope({
            'taxes': [
              {
                'id': 7,
                'name': 'VAT',
                'amount': '8.1',
                'amount_type': 'percent',
                'price_include': false,
              },
              {
                'id': 8,
                'name': 'Levy',
                'amount': '2',
                'amount_type': 'fixed',
                'price_include': false,
              },
            ],
            'default_tax_ids': [7],
          }),
        ),
      )
      ..on(
        'GET /categories',
        (_) => const FakeReply(200, {
          'data': [
            {'id': 4, 'name': 'Spices', 'parent_id': null},
          ],
          'meta': {'request_id': 'request-1', 'next_cursor': null},
        }),
      );
    expect((await repo.loadTaxes()).map((tax) => tax.label), [
      'VAT (8.1%)',
      'Levy',
    ]);
    expect((await repo.loadCategories()).single.name, 'Spices');
    expect(
      server.called('GET /categories').single.uri.queryParameters['limit'],
      '100',
    );
    server.on(
      'GET /taxes',
      (_) => FakeReply(
        200,
        successEnvelope({
          'taxes': [
            {'id': 0},
          ],
        }),
      ),
    );
    await expectLater(repo.loadTaxes(), _kind(FailureKind.protocol));
  });

  group('stock adjustment', () {
    const adjust = 'POST /products/10/stock-adjustments';
    Map<String, dynamic> acknowledged(String quantity, {int location = 8}) => {
      'product': v2Product(quantity: quantity, version: '4'),
      'adjustment': {
        'id': 31,
        'previous_quantity': '48',
        'new_quantity': quantity,
        'difference': '2',
        'location_id': location,
        'move_id': 77,
        'applied_at': '2026-10-27T08:00:00Z',
      },
    };
    setUp(() {
      server.on(
        adjust,
        (r) => FakeReply(
          201,
          successEnvelope(
            acknowledged(requestBody(r)['new_quantity'] as String),
          ),
        ),
      );
    });

    test(
      'sets the absolute count at the POS location with a version',
      () async {
        final product = await loaded();
        expect(product.stockLocationId, 8);
        expect(product.quantityDecimals, 2);
        final result = await repo.adjustStock(
          product,
          StockCount.parse('50,5', maxDecimals: product.quantityDecimals),
        );
        expect(result.product.stock, 50.5);
        expect(result.product.version, '4');
        expect(result.previousQuantity, 48);
        expect(result.newQuantity, 50.5);
        final request = server.called(adjust).single;
        expect(requestBody(request), {
          'new_quantity': '50.5',
          'location_id': 8,
          'reason': 'count',
        });
        expect(request.headers['If-Match'], '"3"');
        expect(request.headers['Idempotency-Key'], matches(_uuid));
      },
    );

    test('non-adjustable stock is never sent', () async {
      server.on(
        scan,
        (_) => FakeReply(
          200,
          successEnvelope({
            ...v2Product(),
            'stock': {
              'tracked': true,
              'quantity': '48',
              'uom': {'id': 1, 'name': 'Units', 'rounding': '1'},
              'location_id': 8,
              // Packaged or owner-specific stock at the location.
              'adjustable': false,
            },
          }),
        ),
      );
      final product = await loaded();
      expect(product.stockAdjustable, isFalse);
      expect(product.quantityDecimals, 0);
      await expectLater(
        repo.adjustStock(product, StockCount.parse('5')),
        _kind(FailureKind.validation),
      );
      expect(server.called(adjust), isEmpty);
    });

    test('backend business rules and validation stay typed', () async {
      final product = await loaded();
      server.on(
        adjust,
        (_) => FakeReply(422, errorEnvelope('BUSINESS_RULE_VIOLATION')),
      );
      await expectLater(
        repo.adjustStock(product, StockCount.parse('5')),
        _kind(FailureKind.validation),
      );
      server.on(
        adjust,
        (_) => FakeReply(403, errorEnvelope('PERMISSION_DENIED')),
      );
      await expectLater(
        repo.adjustStock(product, StockCount.parse('5')),
        _kind(FailureKind.forbidden),
      );
      expect(signOuts, 0);
    });

    test('a stale version is a conflict and is never retried', () async {
      final product = await loaded();
      server.on(
        adjust,
        (_) => FakeReply(412, errorEnvelope('VERSION_CONFLICT')),
      );
      await expectLater(
        repo.adjustStock(product, StockCount.parse('5')),
        _kind(FailureKind.conflict),
      );
      expect(server.called(adjust), hasLength(1));
    });

    test('an uncertain count reuses its key; a new count does not', () async {
      final product = await loaded();
      server.on(
        adjust,
        (r) => throw DioException(
          requestOptions: r,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(
        repo.adjustStock(product, StockCount.parse('5')),
        _kind(FailureKind.network),
      );
      server.on(
        adjust,
        (r) => FakeReply(
          201,
          successEnvelope(
            acknowledged(requestBody(r)['new_quantity'] as String),
          ),
        ),
      );
      await repo.adjustStock(product, StockCount.parse('5'));
      await repo.adjustStock(product, StockCount.parse('6'));
      final keys = [
        for (final r in server.called(adjust)) r.headers['Idempotency-Key'],
      ];
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
    });

    for (final (label, data) in [
      ('different count', acknowledged('5')),
      ('different location', acknowledged('6', location: 9)),
      ('missing adjustment', {'product': v2Product(quantity: '6')}),
      ('product only', v2Product(quantity: '6')),
    ]) {
      test('a mismatched acknowledgement is never success ($label)', () async {
        final product = await loaded();
        server.on(adjust, (_) => FakeReply(201, successEnvelope(data)));
        await expectLater(
          repo.adjustStock(product, StockCount.parse('6')),
          _kind(FailureKind.protocol),
        );
      });
    }
  });

  group('stock movements', () {
    const move = 'POST /products/10/stock-movements';
    Map<String, dynamic> moved(
      String operation,
      String quantity, {
      required String result,
      String previous = '48',
      int location = 8,
    }) => {
      'product': v2Product(quantity: result, version: '4'),
      'movement': {
        'id': 41,
        'operation': operation,
        'quantity': quantity,
        'previous_quantity': previous,
        'new_quantity': result,
        'difference': '0',
        'location_id': location,
        'move_id': 78,
        'applied_at': '2026-10-27T08:00:00Z',
      },
    };

    for (final (operation, name, result) in [
      (StockOperation.add, 'add', '58'),
      (StockOperation.remove, 'remove', '38'),
    ]) {
      test('$name sends the quantity, the version and a key', () async {
        server.on(
          move,
          (_) => FakeReply(
            201,
            successEnvelope(moved(name, '10', result: result)),
          ),
        );
        final product = await loaded();
        final applied = await repo.adjustStock(
          product,
          StockCount.parse('10', maxDecimals: 2),
          operation: operation,
        );
        // The backend result is shown, not a client-side calculation.
        expect(applied.product.stock, double.parse(result));
        expect(applied.newQuantity, double.parse(result));
        expect(applied.previousQuantity, 48);
        expect(applied.operation, operation);
        final request = server.called(move).single;
        expect(requestBody(request), {
          'operation': name,
          'quantity': '10',
          'location_id': 8,
        });
        expect(request.headers['If-Match'], '"3"');
        expect(request.headers['Idempotency-Key'], matches(_uuid));
        expect(server.called('POST /products/10/stock-adjustments'), isEmpty);
      });
    }

    test('the server result wins over the client preview', () async {
      // Stock changed meanwhile on the server: 48 + 10 is not 62.
      server.on(
        move,
        (_) => FakeReply(
          201,
          successEnvelope(moved('add', '10', previous: '52', result: '62')),
        ),
      );
      final applied = await repo.adjustStock(
        await loaded(),
        StockCount.parse('10'),
        operation: StockOperation.add,
      );
      expect(applied.newQuantity, 62);
      expect(applied.previousQuantity, 52);
    });

    test('a version conflict is typed and never retried', () async {
      server.on(move, (_) => FakeReply(412, errorEnvelope('VERSION_CONFLICT')));
      await expectLater(
        repo.adjustStock(
          await loaded(),
          StockCount.parse('1'),
          operation: StockOperation.remove,
        ),
        _kind(FailureKind.conflict),
      );
      expect(server.called(move), hasLength(1));
    });

    test('permission and business rules stay typed', () async {
      final product = await loaded();
      server.on(
        move,
        (_) => FakeReply(403, errorEnvelope('PERMISSION_DENIED')),
      );
      await expectLater(
        repo.adjustStock(
          product,
          StockCount.parse('1'),
          operation: StockOperation.add,
        ),
        _kind(FailureKind.forbidden),
      );
      server.on(
        move,
        (_) => FakeReply(422, errorEnvelope('BUSINESS_RULE_VIOLATION')),
      );
      await expectLater(
        repo.adjustStock(
          product,
          StockCount.parse('1'),
          operation: StockOperation.remove,
        ),
        _kind(FailureKind.validation),
      );
      expect(signOuts, 0);
    });

    test(
      'an uncertain write reuses its key; another quantity does not',
      () async {
        final product = await loaded();
        server.on(
          move,
          (r) => throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          ),
        );
        await expectLater(
          repo.adjustStock(
            product,
            StockCount.parse('5'),
            operation: StockOperation.add,
          ),
          _kind(FailureKind.network),
        );
        server.on(
          move,
          (r) =>
              FakeReply(201, successEnvelope(moved('add', '5', result: '53'))),
        );
        await repo.adjustStock(
          product,
          StockCount.parse('5'),
          operation: StockOperation.add,
        );
        server.on(
          move,
          (r) =>
              FakeReply(201, successEnvelope(moved('add', '6', result: '54'))),
        );
        await repo.adjustStock(
          product,
          StockCount.parse('6'),
          operation: StockOperation.add,
        );
        // Add and Remove of the same quantity are different intents too.
        final keys = [
          for (final r in server.called(move)) r.headers['Idempotency-Key'],
        ];
        expect(keys[1], keys[0]);
        expect(keys[2], isNot(keys[0]));
      },
    );

    test('non-adjustable stock is never sent', () async {
      server.on(
        scan,
        (_) => FakeReply(
          200,
          successEnvelope({
            ...v2Product(),
            'stock': {
              'tracked': true,
              'quantity': '48',
              'uom': {'id': 1, 'name': 'Units', 'rounding': '1'},
              'location_id': 8,
              'adjustable': false,
            },
          }),
        ),
      );
      await expectLater(
        repo.adjustStock(
          await loaded(),
          StockCount.parse('5'),
          operation: StockOperation.add,
        ),
        _kind(FailureKind.validation),
      );
      expect(server.called(move), isEmpty);
    });

    for (final (label, data) in [
      ('other operation', moved('remove', '10', result: '38')),
      ('other quantity', moved('add', '11', result: '59')),
      ('other location', moved('add', '10', result: '58', location: 9)),
      ('inconsistent result', moved('add', '10', result: '60')),
      ('negative result', moved('add', '10', previous: '-20', result: '-10')),
      (
        'count answer',
        {
          'product': v2Product(quantity: '58', version: '4'),
          'adjustment': {
            'id': 1,
            'previous_quantity': '48',
            'new_quantity': '58',
          },
        },
      ),
      ('product only', v2Product(quantity: '58')),
    ]) {
      test('a mismatched acknowledgement is never success ($label)', () async {
        server.on(move, (_) => FakeReply(201, successEnvelope(data)));
        await expectLater(
          repo.adjustStock(
            await loaded(),
            StockCount.parse('10'),
            operation: StockOperation.add,
          ),
          _kind(FailureKind.protocol),
        );
      });
    }
  });
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
