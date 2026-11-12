import 'dart:ui';

import 'package:flutter/material.dart';

/// Clear, neutral glass for fixed actions, independent of brand fills.
class ProductActionSurface extends StatelessWidget {
  const new({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      boxShadow: [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 16,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCCFFFFFF), Color(0x66FFFFFF), Color(0x99FFFFFF)],
            ),
            border: Border(top: BorderSide(color: Color(0xCCFFFFFF))),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: child,
          ),
        ),
      ),
    ),
  );
}
