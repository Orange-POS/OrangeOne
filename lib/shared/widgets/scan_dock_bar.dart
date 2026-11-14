import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Bottom navigation of the product screens: a solid orange bar with a soft
/// notch, and a round orange scan action raised in the middle, separated
/// from the bar by a white ring.
class ScanDockBar extends StatelessWidget {
  const new({
    required this.onPressed,
    required this.label,
    this.buttonKey,
    this.icon = 'assets/icons/scan_dock.svg',
    super.key,
  });

  final VoidCallback? onPressed;

  /// Tooltip and accessibility label of the action.
  final String label;
  final Key? buttonKey;
  final String icon;

  /// Diameter of the round action.
  static const buttonSize = 60.0;

  /// White ring between the action and the bar.
  static const gap = 5.0;

  /// Height of the orange bar without a bottom safe-area inset (Android
  /// button navigation).
  static const minBarHeight = 24.0;

  /// How far the action rises above the bar.
  static const rise = 40.0;

  /// The part of the action sunk into the bar: the bar shows this much
  /// above a bottom safe-area inset (the iOS home indicator, Android
  /// gesture navigation), so the action ends exactly where the inset
  /// starts and never reaches into it.
  static const double sunk = buttonSize - rise;

  /// Total height of the dock for a bottom safe-area inset of [bottomInset].
  static double heightFor(double bottomInset) =>
      rise + math.max(bottomInset + sunk, minBarHeight);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: heightFor(bottom),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _NotchedBarPainter(
                top: rise,
                notchCenterY: buttonSize / 2,
                notchRadius: buttonSize / 2 + gap,
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Tooltip(
              message: label,
              child: Semantics(
                button: true,
                label: label,
                excludeSemantics: true,
                child: Material(
                  color: OrangeTheme.action,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: buttonKey,
                    onTap: onPressed,
                    customBorder: const CircleBorder(),
                    splashColor: OrangeTheme.actionPressed,
                    child: SizedBox.square(
                      dimension: buttonSize,
                      child: Center(
                        child: SvgPicture.asset(
                          icon,
                          width: 32,
                          height: 32,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The orange bar from [top] down, with a round notch of [notchRadius]
/// around the action and smooth shoulders where the notch meets the edge.
class _NotchedBarPainter extends CustomPainter {
  new({
    required this.top,
    required this.notchCenterY,
    required this.notchRadius,
  });

  final double top;
  final double notchCenterY;
  final double notchRadius;
  Size? _size;

  Path _path(Size size) {
    final cx = size.width / 2;
    final r = notchRadius;
    // Where the notch circle crosses the bar's top edge.
    final dy = top - notchCenterY;
    final half = math.sqrt(math.max(r * r - dy * dy, 0));
    const shoulder = 22.0;
    // How far along the circle the shoulders blend in (radians).
    const blend = .3;
    // Angles (from the centre) of the crossing points, below the centre.
    final start = math.atan2(dy, -half);
    final end = math.atan2(dy, half);
    final notch = Rect.fromCircle(center: Offset(cx, notchCenterY), radius: r);
    return Path()
      ..moveTo(0, top)
      ..lineTo(cx - half - shoulder, top)
      ..quadraticBezierTo(
        cx - half,
        top,
        cx + r * math.cos(start - blend),
        notchCenterY + r * math.sin(start - blend),
      )
      // Through the bottom of the circle (angles decrease, y points down).
      ..arcTo(notch, start - blend, end - start + 2 * blend, false)
      ..quadraticBezierTo(cx + half, top, cx + half + shoulder, top)
      ..lineTo(size.width, top)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    canvas.drawPath(_path(size), Paint()..color = OrangeTheme.action);
  }

  /// Only the orange bar takes touches: the transparent area above it and
  /// inside the notch passes them to the content behind.
  @override
  bool hitTest(Offset position) {
    final size = _size;
    return size != null && _path(size).contains(position);
  }

  @override
  bool shouldRepaint(_NotchedBarPainter old) =>
      old.top != top ||
      old.notchCenterY != notchCenterY ||
      old.notchRadius != notchRadius;
}
