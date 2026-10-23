import 'package:flutter/material.dart';

/// Consistent stock information for product-name cards across features.
class StockBadge extends StatelessWidget {
  const new({
    required this.quantity,
    this.unit = '',
    this.onLightSurface = false,
    this.compact = false,
    super.key,
  });
  final double? quantity;
  final String unit;
  final bool onLightSurface;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final stock = quantity;
    final known = stock != null && stock.isFinite;
    final amount = known
        ? stock.toStringAsFixed(stock == stock.roundToDouble() ? 0 : 2)
        : '';
    final text = known
        ? '${stock > 0 ? 'In stock' : 'Out of stock'} · $amount'
              '${unit.isEmpty ? '' : ' $unit'}'
        : 'Stock unavailable';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: onLightSurface ? .06 : .16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 12 : null,
          height: compact ? 16 / 12 : null,
          fontWeight: compact ? FontWeight.w500 : null,
          color: onLightSurface ? const Color(0xFF5F6368) : Colors.white,
        ),
      ),
    );
  }
}
