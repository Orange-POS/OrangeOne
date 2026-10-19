import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';

import '../../support/product_fakes.dart';

void main() {
  late Dio dio;
  late OdooProductDetailsRepository repository;
  late List<RequestOptions> requests;
  late String scopes;
  late bool supported;
  Map<String, dynamic>? found;
  Map<String, dynamic>? saveResult;
  Map<String, dynamic>? updateResult;
  setUp(() {
    dio = Dio();
    requests = [];
    scopes = 'product:name_update product:price_update reference:read';
    supported = true;
    found = null;
    saveResult = null;
    updateResult = null;
    repository = OdooProductDetailsRepository(
      ProductDetailsRemoteDataSource(
        JsonRpcClient(
          dio,
          const ApiConfiguration(
            baseUrl: 'https://unused.test',
            environment: AppEnvironment.development,
          ),
        ),
        origin: Uri.parse('https://pos.example'),
        token: 'fixture',
        cancelToken: CancelToken(),
      ),
      onSessionRejected: () async {},
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          final path = request.uri.path;
          final result = path.endsWith('/token/check')
              ? {'ok': true, 'scopes': scopes}
              : path.endsWith('/products/find')
              ? {'ok': true, 'product': found}
              : path.endsWith('/references')
              ? {
                  'ok': true,
                  if (supported) 'create_only_supported': true,
                  'taxes': [
                    {
                      'id': 1,
                      'name': 'VAT',
                      'amount': 15,
                      'amount_type': 'percent',
                    },
                  ],
                }
              : path.endsWith('/products/update')
              ? updateResult ?? {'ok': true, 'product': productJson()}
              : saveResult ??
                    {'ok': true, 'action': 'created', 'product': productJson()};
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
  NewProduct draft() => NewProduct(
    barcode: '0010101010',
    name: 'New',
    price: ChfPrice.parse('100.00'),
    taxIds: const [],
  );

  test('rechecks permission and sends create-only with No Tax', () async {
    final result = await repository.createProduct(draft());
    expect(result.id, 10);
    expect(requests.map((request) => request.uri.path), [
      '/mupi/mobile/auth/token/check',
      '/mupi/mobile/api/products/find',
      '/mupi/mobile/api/products/references',
      '/mupi/mobile/api/products/save',
    ]);
    expect((requests.last.data as Map)['params'], {
      'barcode': '0010101010',
      'name': 'New',
      'price': 100.0,
      'tax_ids': <int>[],
      'create_only': true,
    });
    expect(
      requests.every(
        (request) => request.headers['Authorization'] == 'Bearer fixture',
      ),
      isTrue,
    );
  });

  for (final missingScope in [
    'product:name_update',
    'product:price_update',
    'reference:read',
  ]) {
    test('missing $missingScope never sends a save', () async {
      scopes = scopes.replaceAll(missingScope, '');
      await expectLater(
        repository.createProduct(draft()),
        throwsA(isA<AppFailure>()),
      );
      expect(requests.any((r) => r.uri.path.endsWith('/save')), isFalse);
    });
  }
  test(
    'original addon creates without an invented capability or parameter',
    () async {
      supported = false;
      saveResult = {
        'ok': true,
        'message': 'Product created successfully.',
        'product': productJson(),
      };
      expect(
        (await repository.prepareCreation('0010101010')).canCreate,
        isTrue,
      );
      final product = await repository.createProduct(draft());
      expect(product.id, 10);
      final saves = requests
          .where((r) => r.uri.path.endsWith('/save'))
          .toList();
      expect(saves, hasLength(1));
      expect((saves.single.data as Map)['params'], {
        'barcode': '0010101010',
        'name': 'New',
        'price': 100.0,
        'tax_ids': <int>[],
      });
    },
  );
  test(
    'original save default taxes are cleared using confirmed update route',
    () async {
      supported = false;
      saveResult = {
        'ok': true,
        'message': 'Product created successfully.',
        'product': {
          ...productJson(),
          'taxes': [
            {'id': 1, 'name': 'VAT', 'amount': 15, 'amount_type': 'percent'},
          ],
        },
      };
      final product = await repository.createProduct(draft());
      expect(product.taxIds, isEmpty);
      expect(requests.last.uri.path, '/mupi/mobile/api/products/update');
      expect((requests.last.data as Map)['params'], {
        'product_id': 10,
        'name': 'Aachi Fish Fry Masala',
        'tax_ids': <int>[],
      });
    },
  );
  test(
    'failed tax correction cannot report success or retry creation',
    () async {
      supported = false;
      saveResult = {
        'ok': true,
        'message': 'Product created successfully.',
        'product': {
          ...productJson(),
          'taxes': [
            {'id': 1, 'name': 'VAT', 'amount': 15, 'amount_type': 'percent'},
          ],
        },
      };
      updateResult = {
        'ok': false,
        'error': 'Token does not have required permission.',
      };
      await expectLater(
        repository.createProduct(draft()),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
        ),
      );
      expect(requests.where((r) => r.uri.path.endsWith('/save')), hasLength(1));
    },
  );
  test('original updated message is not accepted as creation', () async {
    supported = false;
    saveResult = {
      'ok': true,
      'message': 'Product updated successfully.',
      'product': productJson(),
    };
    await expectLater(
      repository.createProduct(draft()),
      throwsA(same(invalidResponse)),
    );
  });
  test('existing product is a conflict without any write', () async {
    found = productJson();
    await expectLater(
      repository.createProduct(draft()),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          FailureKind.conflict,
        ),
      ),
    );
    expect(requests.any((r) => r.uri.path.endsWith('/save')), isFalse);
  });
  test(
    'race or hidden-barcode server conflict is typed and never retried',
    () async {
      saveResult = {'ok': false, 'error': 'Barcode already exists.'};
      await expectLater(
        repository.createProduct(draft()),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.kind,
            'kind',
            FailureKind.conflict,
          ),
        ),
      );
      expect(requests.where((r) => r.uri.path.endsWith('/save')), hasLength(1));
    },
  );
  test(
    'an updated or malformed acknowledgment is never reported as creation',
    () async {
      saveResult = {'ok': true, 'action': 'updated', 'product': productJson()};
      await expectLater(
        repository.createProduct(draft()),
        throwsA(same(invalidResponse)),
      );
    },
  );
}
