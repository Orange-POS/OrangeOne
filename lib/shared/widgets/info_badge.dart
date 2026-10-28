import 'package:flutter/material.dart';

/// The pill used for product facts (stock, category, barcode) so that all of
/// them share one design.
class InfoBadge extends StatelessWidget {
  const new({
    required this.text,
    this.onLightSurface = false,
    this.compact = false,
    this.singleLine = false,
    this.semanticsLabel,
    super.key,
  });
  final String text;
  final bool onLightSurface;
  final bool compact;

  /// Truncates long text (such as a category name) instead of wrapping it.
  final bool singleLine;

  /// Screen-reader text when [text] alone is ambiguous.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: onLightSurface ? .06 : .16),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      semanticsLabel: semanticsLabel,
      maxLines: singleLine ? 1 : null,
      overflow: singleLine ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: compact ? 12 : null,
        height: compact ? 16 / 12 : null,
        fontWeight: compact ? FontWeight.w500 : null,
        color: onLightSurface ? const Color(0xFF5F6368) : Colors.white,
      ),
    ),
  );
}
