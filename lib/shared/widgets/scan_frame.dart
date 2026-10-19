import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/brand_gradient.dart';

/// Open-corner scanner layout border, separate from the live camera preview.
class ScanFrame extends StatelessWidget {
  const new({this.color = OrangeTheme.brand, super.key});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final frame = Stack(
      children: [
        for (final alignment in [
          Alignment.topLeft,
          Alignment.topRight,
          Alignment.bottomLeft,
          Alignment.bottomRight,
        ])
          Align(
            alignment: alignment,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                border: Border(
                  top: alignment.y < 0
                      ? BorderSide(color: color, width: 6)
                      : BorderSide.none,
                  bottom: alignment.y > 0
                      ? BorderSide(color: color, width: 6)
                      : BorderSide.none,
                  left: alignment.x < 0
                      ? BorderSide(color: color, width: 6)
                      : BorderSide.none,
                  right: alignment.x > 0
                      ? BorderSide(color: color, width: 6)
                      : BorderSide.none,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: alignment == Alignment.topLeft
                      ? const Radius.circular(14)
                      : Radius.zero,
                  topRight: alignment == Alignment.topRight
                      ? const Radius.circular(14)
                      : Radius.zero,
                  bottomLeft: alignment == Alignment.bottomLeft
                      ? const Radius.circular(14)
                      : Radius.zero,
                  bottomRight: alignment == Alignment.bottomRight
                      ? const Radius.circular(14)
                      : Radius.zero,
                ),
              ),
            ),
          ),
      ],
    );
    return color == OrangeTheme.brand ? BrandGradient(child: frame) : frame;
  }
}
