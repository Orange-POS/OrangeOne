import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
                      MediaQuery.paddingOf(context).top + 16,
                      height * 75 / 844,
                    ),
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 48,
                          child: IconButton(
                            key: const Key('logout-button'),
                            tooltip: 'Logout',
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
                      label: 'Scan product barcode',
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
                      child: const Column(
                        children: [
                          Text(
                            'Tap to scan Barcode',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Scan Your Product',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: math.max<double>(
                      MediaQuery.paddingOf(context).bottom + 16,
                      height * 42 / 844,
                    ),
                    child: const Text(
                      'Powered By OrangeONE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.4,
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
