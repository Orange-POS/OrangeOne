import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/mobile_api_fakes.dart';
import '../../../support/product_api_fakes.dart';
import '../../../support/product_fakes.dart';

void main() {
  const scan = 'GET /products/by-barcode/0010101010';
  late FakeMobileApiServer server;
  late OdooProductRepository repository;
  late int invalidations;
  setUp(() {
    server = FakeMobileApiServer()
      ..on(scan, (_) => FakeReply(200, successEnvelope(v2Product())));
    invalidations = 0;
    repository = OdooProductRepository(
      ProductRemoteDataSource(
        fakeProductApi(server),
        cancelToken: CancelToken(),
      ),
      onSessionRejected: () async {
        invalidations++;
      },
    );
  });

  void reply(int status, Object? body) =>
      server.on(scan, (_) => FakeReply(status, body));

  test(
    'finds a product by exact barcode on the session API with its token',
    () async {
      final product = await repository.findByBarcode(fixtureProduct.barcode);
      expect(product?.id, 10);
      expect(product?.stockQuantity, 48);
      expect(product?.price, 100);
      expect(product?.unit, 'Units');
      expect(product?.reference, 'MASALA');
      final request = server.requests.single;
      expect(
        request.uri.toString(),
        '$testApiBase/products/by-barcode/0010101010',
      );
      expect(request.headers['Authorization'], 'Bearer oa_fixture');
    },
  );
  test('barcodes are path-encoded', () async {
    server.on(
      'GET /products/by-barcode/A%2FB',
      (_) => FakeReply(200, successEnvelope(v2Product(barcode: 'A/B'))),
    );
    expect((await repository.findByBarcode('A/B'))?.barcode, 'A/B');
  });
  test('PRODUCT_NOT_FOUND means not found', () async {
    reply(404, errorEnvelope('PRODUCT_NOT_FOUND'));
    expect(await repository.findByBarcode(fixtureProduct.barcode), isNull);
    expect(invalidations, 0);
  });
  test('untracked stock stays unavailable', () async {
    reply(200, successEnvelope(v2Product(quantity: null)));
    final product = await repository.findByBarcode(fixtureProduct.barcode);
    expect(product?.stockQuantity, isNull);
  });
  test('optional fields are safe and stock can be negative', () async {
    reply(
      200,
      successEnvelope({...v2Product(quantity: '-2.500'), 'default_code': null}),
    );
    final product = await repository.findByBarcode(fixtureProduct.barcode);
    expect(product?.reference, '');
    expect(product?.stockQuantity, -2.5);
  });
  test('invalid barcodes fail validation without a request', () async {
    await expectLater(
      repository.findByBarcode('two words'),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.validation),
      ),
    );
    expect(server.requests, isEmpty);
  });
  for (final payload in [
    null,
    <Object>[],
    {...v2Product(), 'id': 0},
    {...v2Product(), 'name': ''},
    v2Product(barcode: 'different'),
    v2Product(price: '1e3'),
    {
      ...v2Product(),
      'list_price': {'amount': 100, 'currency': 'CHF'},
    },
    {
      ...v2Product(),
      'list_price': {'amount': '100.00', 'currency': 'chf'},
    },
    {...v2Product(), 'stock': null},
    {...v2Product(), 'version': null},
    {...v2Product(), 'permissions': null},
  ]) {
    test('rejects malformed product response $payload', () async {
      reply(200, successEnvelope(payload));
      await expectLater(
        repository.findByBarcode(fixtureProduct.barcode),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
        ),
      );
    });
  }
  for (final code in ['TOKEN_REVOKED', 'TOKEN_INVALID', 'AUTH_REQUIRED']) {
    test('invalidates the session for $code', () async {
      reply(401, errorEnvelope(code));
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
  for (final code in ['PERMISSION_DENIED', 'COMPANY_MISMATCH']) {
    test('$code does not log the user out', () async {
      reply(403, errorEnvelope(code));
      await expectLater(
        repository.findByBarcode(fixtureProduct.barcode),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.forbidden,
          ),
        ),
      );
      expect(invalidations, 0);
    });
  }
  test('server errors without an envelope use a safe message', () async {
    reply(500, 'Sensitive server traceback');
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
