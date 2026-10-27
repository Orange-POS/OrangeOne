import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';

import '../../../support/product_fakes.dart';

void main() {
  late Dio dio;
  late OdooProductRepository repository;
  late Map<String, dynamic> result;
  late List<RequestOptions> requests;
  late int invalidations;
  setUp(() {
    dio = Dio();
    result = {'ok': true, 'product': productJson()};
    requests = [];
    invalidations = 0;
    repository = OdooProductRepository(
      ProductRemoteDataSource(
        JsonRpcClient(
          dio,
          const ApiConfiguration(
            baseUrl: 'https://old.example',
            environment: AppEnvironment.production,
          ),
        ),
        origin: Uri.parse('http://192.168.1.3:8080'),
        accessToken: () async => 'fixture-token',
        cancelToken: CancelToken(),
      ),
      onSessionRejected: () async {
        invalidations++;
      },
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'jsonrpc': '2.0',
                'id': (options.data as Map)['id'],
                'result': result,
              },
            ),
          );
        },
      ),
    );
  });
  tearDown(() => dio.close(force: true));

  test(
    'finds a product using exact barcode, session origin and bearer token',
    () async {
      final product = await repository.findByBarcode(fixtureProduct.barcode);
      expect(product?.id, 10);
      expect(product?.stockQuantity, 48);
      expect(product?.price, 100);
      expect(product?.unit, 'Units');
      expect(
        requests.single.uri.toString(),
        'http://192.168.1.3:8080/mupi/mobile/api/products/find',
      );
      expect(requests.single.headers['Authorization'], 'Bearer fixture-token');
      expect((requests.single.data as Map)['params'], {
        'barcode': '0010101010',
      });
    },
  );
  test('null product means not found', () async {
    result = {'ok': true, 'product': null};
    expect(await repository.findByBarcode(fixtureProduct.barcode), isNull);
  });
  for (final payload in [
    <String, dynamic>{'ok': true},
    <String, dynamic>{
      'ok': true,
      'product': [productJson(), productJson()],
    },
    <String, dynamic>{'ok': true, 'product': false},
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'id': 0},
    },
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'name': ''},
    },
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'barcode': 'different'},
    },
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'price': '100'},
    },
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'price': double.nan},
    },
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'stock_quantity': null},
    },
    <String, dynamic>{
      'ok': true,
      'product': {...productJson(), 'uom': 1},
    },
    <String, dynamic>{'ok': 'true', 'product': null},
  ]) {
    test('rejects malformed or ambiguous product response $payload', () async {
      result = payload;
      await expectLater(
        repository.findByBarcode(fixtureProduct.barcode),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
        ),
      );
    });
  }
  test('optional fields are safe and stock can be negative', () async {
    result = {
      'ok': true,
      'product': {
        ...productJson()..remove('default_code'),
        'uom': false,
        'stock_quantity': -2.5,
      },
    };
    final product = await repository.findByBarcode(fixtureProduct.barcode);
    expect(product?.reference, '');
    expect(product?.unit, '');
    expect(product?.stockQuantity, -2.5);
  });
  for (final message in [
    'Token has expired.',
    'Token is not active.',
    'POS session is no longer opened.',
  ]) {
    test('invalidates session for $message', () async {
      result = {'ok': false, 'error': message};
      await expectLater(
        repository.findByBarcode(fixtureProduct.barcode),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.unauthenticated,
          ),
        ),
      );
      expect(invalidations, 1);
    });
  }
  test('permission denial does not log the user out', () async {
    result = {'ok': false, 'error': 'Token does not have required permission.'};
    await expectLater(
      repository.findByBarcode(fixtureProduct.barcode),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.forbidden),
      ),
    );
    expect(invalidations, 0);
  });
  test('unknown server errors use a safe message', () async {
    result = {'ok': false, 'error': 'Sensitive server traceback'};
    await expectLater(
      repository.findByBarcode(fixtureProduct.barcode),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.message,
          'message',
          isNot(contains('traceback')),
        ),
      ),
    );
  });
}
