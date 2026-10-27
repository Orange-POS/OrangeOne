import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class StockCountConfirmation {
  const new({required this.product, required this.count});
  final ProductDetails product;
  final StockCount count;
}

/// Sets the counted on-hand quantity at the POS stock location.
class AdjustStock {
  const new(this.repository);
  final ProductDetailsRepository repository;

  /// Counting the current quantity again is allowed: the backend records it
  /// as a confirmed count without a stock move.
  StockCount validate(String raw, ProductDetails product) {
    if (!product.stockAdjustable || product.stock == null) {
      throw const FormatException(
        'Stock for this product cannot be counted here.',
      );
    }
    return StockCount.parse(raw, maxDecimals: product.quantityDecimals);
  }

  Future<StockAdjustment> call(StockCountConfirmation confirmation) =>
      repository.adjustStock(confirmation.product, confirmation.count);
}
