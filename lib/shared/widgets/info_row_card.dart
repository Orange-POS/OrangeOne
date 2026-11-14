import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// A bordered one-line card: icon, gray label, right-aligned value and an
/// optional action (usually an `EditPencilButton`), as the Price row of
/// Product Details.
class InfoRowCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.value,
    this.action,
    this.iconSize = 20,
    this.valueKey,
    super.key,
  });

  /// The Price card of the product screens (banknote icon, 24 px).
  const new price({
    required this.label,
    required this.value,
    this.action,
    this.valueKey,
    super.key,
  }) : icon = priceIcon,
       iconSize = 24;

  static const priceIcon = 'assets/icons/product_detail_price.svg';

  /// SVG asset of the leading icon (drawn in its own colors).
  final String icon;
  final String label;
  final String value;
  final Widget? action;
  final double iconSize;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: OrangeTheme.actionDisabled),
    ),
    // Label and value each take at most half of the row and only what they
    // need: a short price leaves the label on one line, and large text on a
    // small phone wraps instead of overflowing. The value group sits right.
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(icon, width: iconSize, height: iconSize),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  key: valueKey,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: OrangeTheme.ink,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action!],
            ],
          ),
        ),
      ],
    ),
  );
}
