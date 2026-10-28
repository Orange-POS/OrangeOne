import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/brand_mark.dart';

/// Authenticated entry to the Home scanner and lookup feature.
class HomePage extends StatelessWidget {
  const new({required this.onScan, required this.onSignOut, super.key});
  final VoidCallback onScan;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(gradient: OrangeTheme.homeGradient),
      child: LayoutBuilder(
        builder: (context, viewport) {
          if (viewport.maxWidth <= 0 || viewport.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final height = math.max<double>(
            viewport.maxHeight,
            740 * MediaQuery.textScalerOf(context).scale(1),
          );
          final circle = math.min<double>(240, viewport.maxWidth - 64);
          final icon = circle * .4;
          return SingleChildScrollView(
            child: SizedBox(
              height: height,
              width: viewport.maxWidth,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: math.max<double>(
                      MediaQuery.paddingOf(context).top,
                      OrangeTheme.topSafeArea,
                    ),
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 48,
                          child: IconButton(
                            key: const Key('logout-button'),
                            tooltip: context.l10n.homeLogoutTooltip,
                            onPressed: onSignOut,
                            iconSize: 20,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: .2,
                              ),
                              shape: const CircleBorder(),
                              fixedSize: const Size.square(48),
                            ),
                            icon: const Icon(Icons.logout),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: BrandMark(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 56),
                      ],
                    ),
                  ),
                  Positioned(
                    top: height * 395 / 844 - circle / 2,
                    child: Semantics(
                      button: true,
                      label: context.l10n.homeScanSemantics,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: const Key('scan-product-button'),
                          onTap: onScan,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: circle,
                            height: circle,
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icons/box_scan.svg',
                                colorFilter: const ColorFilter.mode(
                                  OrangeTheme.scannerAccent,
                                  BlendMode.srcIn,
                                ),
                                width: icon,
                                height: icon,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: height * 554.5 / 844,
                    left: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: onScan,
                      child: Column(
                        children: [
                          Text(
                            context.l10n.homeScanTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.homeScanSubtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
