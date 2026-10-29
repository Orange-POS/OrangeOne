import 'package:flutter/material.dart';
import 'package:orange_one/shared/widgets/info_badge.dart';

/// Texts of a [StockBadge]. The defaults are English; localized screens pass
/// translated values.
class StockBadgeLabels {
  const new({
    this.inStock = 'In stock',
    this.outOfStock = 'Out of stock',
    this.unavailable = 'Stock unavailable',
  });
  final String inStock;
  final String outOfStock;
  final String unavailable;
}

/// "In stock · 48 Units", "Out of stock · 0" or "Stock unavailable"; never an
/// invented quantity.
String stockText(
  double? quantity,
  String unit, [
  StockBadgeLabels labels = const StockBadgeLabels(),
]) {
  final stock = quantity;
  if (stock == null || !stock.isFinite) return labels.unavailable;
  final amount = stock.toStringAsFixed(stock == stock.roundToDouble() ? 0 : 2);
  return '${stock > 0 ? labels.inStock : labels.outOfStock} · $amount'
      '${unit.isEmpty ? '' : ' $unit'}';
}

/// Consistent stock information for product-name cards across features.
class StockBadge extends StatelessWidget {
  const new({
    required this.quantity,
    this.unit = '',
    this.onLightSurface = false,
    this.compact = false,
    this.labels = const StockBadgeLabels(),
    super.key,
  });
  final StockBadgeLabels labels;
  final double? quantity;
  final String unit;
  final bool onLightSurface;
  final bool compact;

  @override
  Widget build(BuildContext context) => InfoBadge(
    text: stockText(quantity, unit, labels),
    onLightSurface: onLightSurface,
    compact: compact,
  );
}
