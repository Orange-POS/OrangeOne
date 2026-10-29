import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class StockCountConfirmation {
  const new({
    required this.product,
    required this.count,
    this.operation = StockOperation.update,
  });
  final ProductDetails product;
  final StockCount count;
  final StockOperation operation;

  /// The stock the user is about to get; a preview, not the backend result.
  double get expectedStock =>
      operation.resultFor(product.stock ?? 0, count.quantity);
}

/// Updates, adds to or removes from the stock at the POS stock location.
class AdjustStock {
  const new(this.repository);
  final ProductDetailsRepository repository;

  /// Counting the current quantity again is allowed: the backend records it
  /// as a confirmed count without a stock move. Add and Remove need a
  /// quantity above zero and Remove cannot take the stock below zero.
  StockCount validate(
    String raw,
    ProductDetails product, {
    StockOperation operation = StockOperation.update,
  }) {
    if (!product.stockAdjustable || product.stock == null) {
      throw const StockInputException(
        StockInputIssue.unavailable,
        'Stock for this product cannot be counted here.',
      );
    }
    final count = StockCount.parse(raw, maxDecimals: product.quantityDecimals);
    if (operation != StockOperation.update && count.quantity <= 0) {
      throw const StockInputException(
        StockInputIssue.zero,
        'Enter a quantity greater than zero.',
      );
    }
    if (operation == StockOperation.remove && count.quantity > product.stock!) {
      throw const StockInputException(
        StockInputIssue.exceedsStock,
        'You cannot remove more than the current stock.',
      );
    }
    return count;
  }

  Future<StockAdjustment> call(StockCountConfirmation confirmation) =>
      repository.adjustStock(
        confirmation.product,
        confirmation.count,
        operation: confirmation.operation,
      );
}
