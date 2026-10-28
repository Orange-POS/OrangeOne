import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/use_cases/adjust_stock.dart';

import '../../../../support/product_details_fakes.dart';

ProductDetails _product({
  double? stock = 150,
  bool adjustable = true,
  int decimals = 0,
}) => ProductDetails(
  id: detailsFixture.id,
  name: detailsFixture.name,
  barcode: detailsFixture.barcode,
  price: detailsFixture.price,
  stock: stock,
  unit: detailsFixture.unit,
  version: detailsFixture.version,
  stockAdjustable: adjustable,
  stockLocationId: 8,
  quantityDecimals: decimals,
);

void main() {
  final useCase = AdjustStock(FakeDetailsRepository());

  StockInputIssue? issue(
    String raw,
    StockOperation operation, {
    ProductDetails? product,
  }) {
    try {
      useCase.validate(raw, product ?? _product(), operation: operation);
    } on StockInputException catch (error) {
      return error.issue;
    }
    return null;
  }

  test('the examples of 150 units', () {
    for (final (operation, result) in [
      (StockOperation.update, 40.0),
      (StockOperation.add, 190.0),
      (StockOperation.remove, 110.0),
    ]) {
      final confirmation = StockCountConfirmation(
        product: _product(),
        count: useCase.validate('40', _product(), operation: operation),
        operation: operation,
      );
      expect(confirmation.expectedStock, result, reason: operation.name);
    }
  });

  test('update accepts zero and the current quantity', () {
    expect(issue('0', StockOperation.update), isNull);
    expect(issue('150', StockOperation.update), isNull);
  });

  for (final operation in [StockOperation.add, StockOperation.remove]) {
    test('${operation.name} needs a quantity above zero', () {
      expect(issue('0', operation), StockInputIssue.zero);
      expect(issue('0.0', operation), StockInputIssue.zero);
      expect(issue('1', operation), isNull);
    });
  }

  test('remove cannot take the stock below zero', () {
    expect(issue('150', StockOperation.remove), isNull);
    expect(issue('151', StockOperation.remove), StockInputIssue.exceedsStock);
    expect(issue('151', StockOperation.add), isNull);
    expect(
      issue(
        '0.5',
        StockOperation.remove,
        product: _product(stock: 0, decimals: 1),
      ),
      StockInputIssue.exceedsStock,
    );
  });

  test('every operation checks format and precision', () {
    for (final operation in StockOperation.values) {
      expect(issue('abc', operation), StockInputIssue.invalid);
      expect(issue('-1', operation), StockInputIssue.invalid);
      expect(issue('', operation), StockInputIssue.invalid);
      expect(issue('1.5', operation), StockInputIssue.wholeNumber);
      expect(
        issue('1.234', operation, product: _product(decimals: 2)),
        StockInputIssue.decimals,
      );
    }
  });

  test('stock that cannot be changed is rejected for every operation', () {
    for (final operation in StockOperation.values) {
      expect(
        issue('1', operation, product: _product(adjustable: false)),
        StockInputIssue.unavailable,
      );
      expect(
        issue('1', operation, product: _product(stock: null)),
        StockInputIssue.unavailable,
      );
    }
  });
}
