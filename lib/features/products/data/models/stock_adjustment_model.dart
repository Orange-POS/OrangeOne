import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

/// Maps the `{product, adjustment}` acknowledgement of a stock count.
abstract final class StockAdjustmentModel {
  static final _decimal = RegExp(r'^-?\d{1,12}(\.\d{1,6})?$');

  /// The acknowledgement must match the count that was sent, at the same
  /// location, and the refreshed product must report the counted stock.
  static StockAdjustment parse(
    Object? data,
    ProductDetails product, {
    required int locationId,
    required double counted,
  }) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final adjustment = data['adjustment'];
    if (adjustment is! Map<String, dynamic>) throw invalidResponse;
    final previous = _number(adjustment['previous_quantity']);
    final applied = _number(adjustment['new_quantity']);
    final location = adjustment['location_id'];
    if (adjustment['id'] is! int ||
        (location != null && location != locationId) ||
        applied != counted ||
        product.stock != counted) {
      throw invalidResponse;
    }
    return StockAdjustment(
      product: product,
      previousQuantity: previous,
      newQuantity: applied,
    );
  }

  static double _number(Object? value) {
    if (value is! String || !_decimal.hasMatch(value)) throw invalidResponse;
    return double.parse(value);
  }
}
