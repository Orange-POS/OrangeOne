import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The Lucide tag of the design system (`assets/icons/tag.svg`), used for
/// discounts. [TagIcon.tile] puts it on the pale orange tile of the
/// discount cards.
class TagIcon extends StatelessWidget {
  const new({this.size = 24, this.color = OrangeTheme.action, super.key})
    : tile = false,
      tileSize = 0;

  const new tile({
    this.size = 24,
    this.tileSize = 56,
    this.color = OrangeTheme.action,
    super.key,
  }) : tile = true;

  final double size;
  final Color color;
  final bool tile;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(
      'assets/icons/tag.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    if (!tile) return icon;
    return Container(
      width: tileSize,
      height: tileSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OrangeTheme.pale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: icon,
    );
  }
}
