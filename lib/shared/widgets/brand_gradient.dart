import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Paint small brand graphics with the same gradient as larger surfaces.
class BrandGradient extends StatelessWidget {
  const new({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: OrangeTheme.gradient.createShader,
    blendMode: BlendMode.srcIn,
    child: child,
  );
}
