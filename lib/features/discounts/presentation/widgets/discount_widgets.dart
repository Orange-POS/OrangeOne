import 'package:flutter/material.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/tag_icon.dart';

const _border = Color(0xFFE8EAED);

/// A white, bordered card of the discount screens (16 px corners, light
/// border, as in the Product Discounts design).
class DiscountPanel extends StatelessWidget {
  const new({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: _border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// The orange tag on a pale tile (discount cards and list rows).
class DiscountTagIcon extends StatelessWidget {
  const new({this.size = 56, super.key});
  final double size;

  @override
  Widget build(BuildContext context) =>
      TagIcon.tile(tileSize: size, size: size * .43);
}

/// The "PRODUCT DISCOUNTS" heading of the discount cards: the outlined tag,
/// the small caps label, the title and an optional action.
class DiscountHeading extends StatelessWidget {
  const new({required this.title, this.trailing, super.key});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const TagIcon(size: 44),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.discountsSectionLabel,
              style: const TextStyle(
                color: OrangeTheme.secondary,
                fontSize: 12,
                height: 16 / 12,
                letterSpacing: .4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  color: OrangeTheme.ink,
                  fontSize: 18,
                  height: 24 / 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

/// The solid orange square "create" action of the design (56 × 56, 12 px
/// corners, white plus in a circle). Disabled: the gray action colors.
class DiscountAddButton extends StatelessWidget {
  const new({required this.tooltip, required this.onPressed, super.key});
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: onPressed == null
            ? OrangeTheme.actionDisabled
            : OrangeTheme.action,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          splashColor: OrangeTheme.actionPressed,
          highlightColor: OrangeTheme.actionPressed,
          child: SizedBox.square(
            dimension: 56,
            child: Icon(
              Icons.add_circle_outline,
              size: 28,
              color: onPressed == null
                  ? OrangeTheme.actionDisabledLabel
                  : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

class DiscountStatusPill extends StatelessWidget {
  const new({required this.status, super.key});
  final DiscountStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      DiscountStatus.active => (
        const Color(0xFFE6F4EA),
        const Color(0xFF137333),
      ),
      DiscountStatus.scheduled => (OrangeTheme.pale, OrangeTheme.dark),
      DiscountStatus.paused => (
        const Color(0xFFFEF7E0),
        const Color(0xFF8A5300),
      ),
      DiscountStatus.expired ||
      DiscountStatus.archived ||
      DiscountStatus.unknown => (
        const Color(0xFFF1F3F4),
        OrangeTheme.secondary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        DiscountText.status(context.l10n, status),
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// An inline message (offline, read-only, conflict, server rule).
class DiscountNotice extends StatelessWidget {
  const new({required this.message, this.error = false, super.key});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFCE8E6) : OrangeTheme.pale,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? const Color(0xFFA50E0E) : OrangeTheme.ink,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    ),
  );
}

/// Confirms a discount write before anything is sent.
class DiscountConfirmDialog extends StatelessWidget {
  const new({required this.title, required this.message, super.key});
  final String title;
  final String message;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            DiscountConfirmDialog(title: title, message: message),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('discount-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}

/// One row of a discount list: tag, title, type, details and an action.
class DiscountListTile extends StatelessWidget {
  const new({
    required this.discount,
    this.subtitle,
    this.onTap,
    this.trailing,
    super.key,
  });

  final Discount discount;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DiscountPanel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const DiscountTagIcon(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DiscountText.title(l10n, discount),
                  style: const TextStyle(
                    color: OrangeTheme.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DiscountText.typeLong(l10n, discount.type),
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 13,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: OrangeTheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 6),
                DiscountStatusPill(status: discount.status),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
