import 'package:flutter/material.dart';
import 'package:orange_one/core/platform/haptics.dart';
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

/// "Multiple discounts active": the card's discount is in effect at the same
/// time as another discount of the product. Orange text with a small
/// warning icon in the card's top-right corner, on the title's line.
class DiscountOverlapWarning extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final text = context.l10n.discountOverlapWarning;
    return Semantics(
      label: text,
      excludeSemantics: true,
      // One line with the icon right before the text; scaled down instead of
      // wrapping when a long translation does not fit beside the title.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 12,
              color: OrangeTheme.action,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: OrangeTheme.action,
                fontSize: 10,
                height: 14 / 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
  const new({
    required this.title,
    required this.message,
    this.confirmLabel,
    super.key,
  });
  final String title;
  final String message;

  /// The confirm button's text; Confirm when null.
  final String? confirmLabel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => DiscountConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
        ),
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
          onPressed: () {
            playHaptic(context, HapticEffect.confirm);
            Navigator.pop(context, true);
          },
          child: Text(confirmLabel ?? l10n.commonConfirm),
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
    this.overlapping = false,
    super.key,
  });

  final Discount discount;
  final String? subtitle;

  /// Shows "Multiple discounts active" in the top-right corner, on the
  /// title's line; the action then sits below it, beside the details.
  final bool overlapping;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = Text(
      DiscountText.title(l10n, discount),
      style: const TextStyle(
        color: OrangeTheme.ink,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DiscountText.typeLong(l10n, discount.type),
          style: const TextStyle(color: OrangeTheme.secondary, fontSize: 13),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: const TextStyle(color: OrangeTheme.secondary, fontSize: 13),
          ),
        const SizedBox(height: 6),
        DiscountStatusPill(status: discount.status),
      ],
    );
    return DiscountPanel(
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(16, 12, overlapping ? 12 : 8, 12),
      child: Row(
        children: [
          const DiscountTagIcon(),
          const SizedBox(width: 16),
          Expanded(
            child: overlapping
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The title's line runs to the card's edge, with the
                      // warning at its end (above the action).
                      // The title keeps its own width (a price or a short
                      // offer), at most 55% of the line; the warning takes
                      // the rest and wraps only when it does not fit. A
                      // table, not a LayoutBuilder: Product Details sizes
                      // its panel with intrinsic dimensions.
                      Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        columnWidths: const {
                          0: MinColumnWidth(
                            IntrinsicColumnWidth(),
                            FractionColumnWidth(.55),
                          ),
                          1: FixedColumnWidth(8),
                          2: FlexColumnWidth(),
                        },
                        children: [
                          TableRow(
                            children: [
                              title,
                              const SizedBox.shrink(),
                              Align(
                                alignment: Alignment.centerRight,
                                child: DiscountOverlapWarning(
                                  key: Key('discount-overlap-${discount.id}'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(child: details),
                          ?trailing,
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 2), details],
                  ),
          ),
          if (!overlapping) ?trailing,
        ],
      ),
    );
  }
}
