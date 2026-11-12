import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The app's one edit action: the Lucide pencil of the design system in a
/// 48 × 48 touch target. Orange on white panels, white on the product
/// gradient; a null [onPressed] shows it disabled (38 % opacity).
class EditPencilButton extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.onPressed,
    this.color = OrangeTheme.action,
    this.size = 24,
    super.key,
  });

  /// Pencil on the orange product gradient.
  const new onGradient({
    required this.tooltip,
    required this.onPressed,
    this.size = 24,
    super.key,
  }) : color = Colors.white;

  static const asset = 'assets/icons/product_detail_pencil.svg';

  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: Opacity(
      opacity: onPressed == null ? .38 : 1,
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    ),
  );
}
