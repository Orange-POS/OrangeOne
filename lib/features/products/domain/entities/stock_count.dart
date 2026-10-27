import 'package:orange_one/features/products/domain/entities/product_details.dart';

/// An absolute, counted on-hand quantity for one product.
class StockCount {
  const new _(this.text, this.quantity);

  /// Accepts a non-negative count with at most [maxDecimals] decimals
  /// (the unit rounding; 6 when unknown).
  factory parse(String raw, {int? maxDecimals}) {
    final value = raw.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d{1,12})(?:\.(\d{1,6}))?$').firstMatch(value);
    if (match == null) {
      throw const FormatException(
        'Enter the counted quantity as a non-negative number.',
      );
    }
    final fraction = match.group(2) ?? '';
    final decimals = maxDecimals ?? 6;
    if (fraction.replaceFirst(RegExp(r'0+$'), '').length > decimals) {
      throw FormatException(
        decimals == 0
            ? 'Enter a whole number for this unit.'
            : 'Use at most $decimals decimal places for this unit.',
      );
    }
    final whole = match.group(1)!.replaceFirst(RegExp('^0+(?=.)'), '');
    final text = fraction.isEmpty ? whole : '$whole.$fraction';
    return StockCount._(text, double.parse(text));
  }

  /// Normalized decimal text sent to the backend (`12.5`, never `12,5`).
  final String text;
  final double quantity;
}

/// A confirmed inventory adjustment and the refreshed product.
class StockAdjustment {
  const new({
    required this.product,
    required this.previousQuantity,
    required this.newQuantity,
  });
  final ProductDetails product;
  final double previousQuantity;
  final double newQuantity;
  double get difference => newQuantity - previousQuantity;
}
