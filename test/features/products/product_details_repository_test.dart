import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';

import '../../support/product_fakes.dart';

void main() {
  late Dio dio;
  late OdooProductDetailsRepository repo;
  late List<RequestOptions> requests;
  late Map<String, dynamic> result;
  late int signOuts;
  setUp(() {
    dio = Dio();
    requests = [];
    signOuts = 0;
    result = {'ok': true, 'product': productJson()};
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
                'result':
                    request.path.endsWith('/token/check') &&
                        result['ok'] == true
                    ? {'ok': true, 'scopes': 'product:read product:name_update'}
                    : result,
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
    test(
      'first $type during details check logs out without product fetch',
      () async {
        dio.interceptors.clear();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              handler.reject(DioException(requestOptions: options, type: type));
            },
          ),
        );
        await expectLater(repo.load('0010101010'), throwsA(isA<AppFailure>()));
        expect(signOuts, 1);
        expect(requests, hasLength(1));
        expect(requests.single.path, endsWith('/token/check'));
      },
    );
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
  test('reads details and server scopes from the session origin', () async {
    final value = await repo.load('0010101010');
    expect(value.product?.name, fixtureProduct.name);
    expect(value.access.editName, isTrue);
    expect(value.access.updatePrice, isFalse);
    expect(
      requests.every((r) => r.uri.origin == 'http://192.168.1.3:8080'),
      isTrue,
    );
    expect((requests.last.data as Map)['params'], {'barcode': '0010101010'});
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
      result = {'ok': true, 'product': null};
      expect((await repo.load('0010101010')).product, isNull);
      result = {'ok': true, 'product': <Object>[]};
      await expectLater(
        repo.load('0010101010'),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
        ),
      );
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
    result = {'ok': false, 'error': 'Token has expired.'};
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
