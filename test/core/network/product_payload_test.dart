import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/product_payload.dart';

import '../../support/product_api_fakes.dart';

Matcher get _protocol => throwsA(
  isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.protocol),
);

void main() {
  group('barcode path', () {
    test('encodes reserved characters', () {
      expect(
        ProductPayload.byBarcodePath('A/B?#%'),
        '/products/by-barcode/A%2FB%3F%23%25',
      );
    });

    for (final barcode in ['', ' ', 'a b', '.', '..', 'é', 'x' * 65]) {
      test('rejects "$barcode" as validation', () {
        expect(
          () => ProductPayload.byBarcodePath(barcode),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.validation,
            ),
          ),
        );
      });
    }
  });

  group('product record', () {
    test('maps a product to cache-compatible fields plus v2 extras', () {
      final record = ProductPayload.productRecord(v2Product());

      expect(record, {
        'id': 10,
        'name': 'Aachi Fish Fry Masala',
        'barcode': '0010101010',
        'price': 100.0,
        'stock_quantity': 48.0,
        'uom': 'Units',
        'default_code': 'MASALA',
        'taxes': [
          {'id': 7, 'name': 'VAT', 'amount': 8.1, 'amount_type': 'percent'},
        ],
        'currency': 'CHF',
        'category': {'id': 4, 'name': 'Spices'},
        'description': 'The Key to Crispy, Flavorful Fish',
        'version': '3',
        'stock_tracked': true,
        'stock_adjustable': true,
        'permissions': productPermissions(),
      });
    });

    test('integral tax amounts stay integers for labels', () {
      final payload = v2Product();
      ((payload['taxes'] as List).first as Map)['amount'] = '15.0000';

      final taxes = ProductPayload.productRecord(payload)['taxes'] as List;

      expect((taxes.single as Map)['amount'], 15);
      expect((taxes.single as Map)['amount'], isA<int>());
    });

    test('untracked stock, missing category and barcode are null', () {
      final record = ProductPayload.productRecord({
        ...v2Product(quantity: null, barcode: null),
        'category': null,
      });

      expect(record['stock_quantity'], isNull);
      expect(record['stock_adjustable'], isFalse);
      expect(record['category'], isNull);
      expect(record['barcode'], isNull);
    });

    for (final (label, change)
        in <(String, void Function(Map<String, dynamic>))>[
          ('non-map payload', (p) => p.clear()),
          (
            'numeric price',
            (p) => p['list_price'] = {'amount': 1, 'currency': 'CHF'},
          ),
          (
            'exponent price',
            (p) => p['list_price'] = {'amount': '1e3', 'currency': 'CHF'},
          ),
          (
            'bad currency',
            (p) => p['list_price'] = {'amount': '1.00', 'currency': 'chf'},
          ),
          ('numeric quantity', (p) => (p['stock'] as Map)['quantity'] = 4),
          ('missing uom', (p) => (p['stock'] as Map).remove('uom')),
          ('missing version', (p) => p.remove('version')),
          ('empty version', (p) => p['version'] = ''),
          (
            'string permission',
            (p) => p['permissions'] = {'product_read': 'yes'},
          ),
          (
            'bad tax',
            (p) => p['taxes'] = [
              {'id': 0},
            ],
          ),
          (
            'bad category',
            (p) => p['category'] = {'id': 'x', 'name': 'Spices'},
          ),
        ]) {
      test('rejects $label', () {
        final payload = v2Product();
        change(payload);
        expect(() => ProductPayload.productRecord(payload), _protocol);
      });
    }
  });

  group('summary record', () {
    test('maps price, currency and nullable stock', () {
      expect(
        ProductPayload.summaryRecord({
          'id': 11,
          'name': 'Service',
          'barcode': null,
          'list_price': {'amount': '5.50', 'currency': 'EUR'},
          'stock_quantity': null,
        }),
        {
          'id': 11,
          'name': 'Service',
          'barcode': null,
          'price': 5.5,
          'currency': 'EUR',
          'stock_quantity': null,
        },
      );
    });

    test('rejects a missing price', () {
      expect(
        () => ProductPayload.summaryRecord({'id': 11, 'name': 'Service'}),
        _protocol,
      );
    });
  });
}
