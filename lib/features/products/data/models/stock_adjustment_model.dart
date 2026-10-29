import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

/// Maps the acknowledgement of a stock change: `{product, adjustment}` for an
/// update (count) and `{product, movement}` for an add or remove.
abstract final class StockAdjustmentModel {
  static final _decimal = RegExp(r'^-?\d{1,12}(\.\d{1,6})?$');

  /// The acknowledgement must match the request that was sent, at the same
  /// location, and the refreshed product must report the stock the backend
  /// says it applied. For add and remove that stock is the backend's own
  /// result (never a client-side calculation); only its internal consistency
  /// is checked.
  static StockAdjustment parse(
    Object? data,
    ProductDetails product, {
    required int locationId,
    required StockOperation operation,
    required double amount,
  }) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final moved = operation != StockOperation.update;
    final entry = data[moved ? 'movement' : 'adjustment'];
    if (entry is! Map<String, dynamic>) throw invalidResponse;
    final previous = _number(entry['previous_quantity']);
    final applied = _number(entry['new_quantity']);
    final location = entry['location_id'];
    if (entry['id'] is! int ||
        (location != null && location != locationId) ||
        product.stock != applied) {
      throw invalidResponse;
    }
    if (moved) {
      if (entry['operation'] != operation.movementName ||
          _number(entry['quantity']) != amount ||
          (operation.resultFor(previous, amount) - applied).abs() > 1e-6 ||
          applied < 0) {
        throw invalidResponse;
      }
    } else if (applied != amount) {
      throw invalidResponse;
    }
    return StockAdjustment(
      product: product,
      previousQuantity: previous,
      newQuantity: applied,
      operation: operation,
    );
  }

  static double _number(Object? value) {
    if (value is! String || !_decimal.hasMatch(value)) throw invalidResponse;
    return double.parse(value);
  }
}
