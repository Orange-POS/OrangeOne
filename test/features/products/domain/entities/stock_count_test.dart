import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

void main() {
  for (final MapEntry(key: raw, value: text) in {
    '48': '48',
    ' 0 ': '0',
    '007': '7',
    '12,5': '12.5',
    '0.25': '0.25',
    '3.10': '3.10',
  }.entries) {
    test('accepts "$raw" as $text', () {
      expect(StockCount.parse(raw, maxDecimals: 2).text, text);
    });
  }

  for (final raw in ['', '-1', 'abc', '1e3', '1.', '.5', '1,000.5', 'NaN']) {
    test('rejects "$raw"', () {
      expect(() => StockCount.parse(raw), throwsFormatException);
    });
  }

  test('the unit rounding limits decimals', () {
    expect(
      () => StockCount.parse('1.5', maxDecimals: 0),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Enter a whole number for this unit.',
        ),
      ),
    );
    expect(
      () => StockCount.parse('1.234', maxDecimals: 2),
      throwsFormatException,
    );
    // Insignificant trailing zeros do not count.
    expect(StockCount.parse('2.000', maxDecimals: 0).quantity, 2);
    expect(StockCount.parse('1.123456').quantity, 1.123456);
  });

  group('operations', () {
    test('the result follows the operation', () {
      expect(StockOperation.update.resultFor(150, 40), 40);
      expect(StockOperation.add.resultFor(150, 40), 190);
      expect(StockOperation.remove.resultFor(150, 40), 110);
      expect(StockOperation.add.resultFor(150.1, 40.2), 190.3);
      expect(StockOperation.remove.resultFor(0.3, 0.1), 0.2);
    });

    test('only add and remove are stock movements', () {
      expect(StockOperation.update.movementName, isNull);
      expect(StockOperation.add.movementName, 'add');
      expect(StockOperation.remove.movementName, 'remove');
    });

    test('rejections carry a localizable reason', () {
      StockInputException reason(String raw, {int? decimals}) {
        try {
          StockCount.parse(raw, maxDecimals: decimals);
        } on StockInputException catch (error) {
          return error;
        }
        fail('accepted $raw');
      }

      expect(reason('x').issue, StockInputIssue.invalid);
      expect(reason('1.5', decimals: 0).issue, StockInputIssue.wholeNumber);
      final decimals = reason('1.234', decimals: 2);
      expect(decimals.issue, StockInputIssue.decimals);
      expect(decimals.decimals, 2);
    });
  });
}
