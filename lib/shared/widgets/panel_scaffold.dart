import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// A fixed branded header (back button and centered title) above a white
/// panel with rounded top corners that holds [body]. Used by Settings and the
/// screens opened from it.
class PanelScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.onBack,
    required this.body,
    this.backButtonKey,
    super.key,
  });

  final String title;
  final VoidCallback onBack;

  /// The panel content, usually a scrolling list.
  final Widget body;
  final Key? backButtonKey;

  static const _headerHeight = 80.0;
  static const _panelRadius = 24.0;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    // The gradient spans the header and the corners of the panel below it,
    // so it runs from dark to light across the header as designed.
    final header =
        math.max(insets.top, OrangeTheme.topSafeArea) + _headerHeight;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: header + _panelRadius,
            child: const DecoratedBox(
              decoration: BoxDecoration(gradient: OrangeTheme.gradient),
            ),
          ),
          Column(
            children: [
              SafeArea(
                bottom: false,
                minimum: const EdgeInsets.only(top: OrangeTheme.topSafeArea),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        key: backButtonKey,
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .2),
                          fixedSize: const Size(48, 48),
                        ),
                        icon: SvgPicture.asset(
                          'assets/icons/arrow_left.svg',
                          width: 24,
                          height: 24,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: onBack,
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(_panelRadius),
                    ),
                  ),
                  child: body,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
