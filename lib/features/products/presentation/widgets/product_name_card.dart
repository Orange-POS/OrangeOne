import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/info_badge.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

class ProductNameCard extends ConsumerWidget {
  const new({
    required this.product,
    this.emptyTitle,
    this.detailsLayout = false,
    this.showActions = true,
    this.taxText,
    this.onEdit,
    this.onAdjustStock,
    this.collapse = 0,
    super.key,
  });
  final ProductDetails? product;
  final String? emptyTitle;
  final bool detailsLayout;

  /// Shows the pencil actions; the editing screens hide them.
  final bool showActions;

  /// The text of the Tax row between the stock and the barcode; null hides it.
  final String? taxText;
  final VoidCallback? onEdit;

  /// Opens Update Stock; null keeps the stock action disabled.
  final VoidCallback? onAdjustStock;

  /// How far the details layout is folded while its screen scrolls: 0 shows
  /// the full card, 1 the compact card without the Tax and Barcode rows and
  /// with less spacing. Every step in between changes the height linearly.
  final double collapse;

  /// The share of the Tax and Barcode rows still shown.
  double get _open => 1 - collapse.clamp(0.0, 1.0);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = product;
    // A product created without a stock quantity has no stock set yet, which
    // is not the same as a counted zero.
    final stockNotSet =
        current != null &&
        (current.stock ?? 0) == 0 &&
        ref.watch(unsetStockProvider).contains(current.id);
    return _card(context, stockNotSet);
  }

  /// The hero is a glass card: a blurred, barely tinted pane with a thin white
  /// edge and a soft shadow. The scaffold's gradient shows through it.
  Widget _glass(Widget child) => Stack(
    clipBehavior: Clip.none,
    children: [
      // The shadow is clipped away inside the card: under a translucent pane
      // it would darken the glass and change the theme colors.
      Positioned.fill(
        child: ClipPath(
          clipper: const _OutsideClipper(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(0, 4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x1AFFF3E8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: .5),
            ),
            child: child,
          ),
        ),
      ),
    ],
  );

  Widget _card(BuildContext context, bool stockNotSet) => Container(
    padding: EdgeInsets.fromLTRB(16, 0, 16, detailsLayout ? 8 + 8 * _open : 24),
    child: detailsLayout
        ? _glass(_detailsContent(context, stockNotSet))
        : _glass(_compactContent(context, stockNotSet)),
  );

  /// The short glass card of the discount screens: name, description (or
  /// the internal reference) and the stock pill. No logo, no actions.
  Widget _compactContent(BuildContext context, bool stockNotSet) {
    final subtitle = product?.description?.trim().isNotEmpty ?? false
        ? product!.description!.trim()
        : product?.reference ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product?.name ?? emptyTitle ?? context.l10n.productNotFound,
          style: const TextStyle(
            fontSize: 28,
            height: 36 / 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 16,
                height: 24 / 16,
                color: Colors.white,
              ),
            ),
          ),
        const SizedBox(height: 16),
        StockBadge(
          quantity: stockNotSet ? null : product?.stock,
          unit: product?.unit ?? '',
          compact: true,
          labels: _stockLabels(context, stockNotSet),
        ),
      ],
    );
  }

  StockBadgeLabels _stockLabels(BuildContext context, bool stockNotSet) {
    final l10n = context.l10n;
    return StockBadgeLabels(
      inStock: l10n.stockInStock,
      outOfStock: l10n.stockOutOfStock,
      unavailable: stockNotSet ? l10n.stockNotSet : l10n.stockUnavailable,
    );
  }

  Widget _detailsContent(BuildContext context, bool stockNotSet) {
    final l10n = context.l10n;
    final category = product?.category?.name.trim();
    final categoryText = category == null || category.isEmpty
        ? l10n.categoryNone
        : category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            // The category pill leads the card.
            InfoBadge(
              key: const Key('product-category-badge'),
              text: categoryText,
              semanticsLabel: l10n.categoryLabel(categoryText),
              compact: true,
              singleLine: true,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    product?.name ?? emptyTitle ?? l10n.productNotFound,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 36 / 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (showActions) ...[
                  const SizedBox(width: 10),
                  EditPencilButton.onGradient(
                    tooltip: l10n.detailsEditName,
                    onPressed: onEdit,
                  ),
                ],
              ],
            ),
            if (product?.reference.isNotEmpty ?? false)
              Text(
                product!.reference,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    children: [
                      StockBadge(
                        quantity: stockNotSet ? null : product?.stock,
                        unit: product?.unit ?? '',
                        compact: true,
                        labels: _stockLabels(context, stockNotSet),
                      ),
                    ],
                  ),
                ),
                if (showActions)
                  EditPencilButton.onGradient(
                    tooltip: l10n.detailsUpdateStock,
                    onPressed: onAdjustStock,
                  ),
              ],
            ),
          ],
        ),
        // Fold away (with the gap above them) while the screen scrolls; the
        // rows above stay.
        ?_fold(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                if (taxText case final tax?)
                  _fact(
                    key: const Key('product-tax-row'),
                    asset: 'assets/icons/product_detail_tax.svg',
                    label: l10n.detailsTax,
                    value: tax,
                  ),
                _fact(
                  key: const Key('product-hero-barcode'),
                  asset: 'assets/icons/product_barcode.svg',
                  label: l10n.detailsBarcode,
                  value: product?.barcode ?? '',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// [child] cut to [_open] of its height and faded alike; null once fully
  /// folded, so the column adds no spacing for it.
  Widget? _fold(Widget child) {
    final open = _open;
    if (open <= 0) return null;
    if (open >= 1) return child;
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: open,
        child: Opacity(opacity: open, child: child),
      ),
    );
  }

  /// An icon, a label and a right-aligned value on a darker pane.
  Widget _fact({
    required Key key,
    required String asset,
    required String label,
    required String value,
  }) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
    );
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            asset,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          const SizedBox(width: 8),
          Text(label, style: style),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style.copyWith(color: const Color(0xFFDADCE0)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything outside a rounded rectangle of the same size as the child.
class _OutsideClipper extends CustomClipper<Path> {
  const new(this.radius);
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Rect.fromLTWH(-40, -40, size.width + 80, size.height + 80))
    ..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );

  @override
  bool shouldReclip(_OutsideClipper oldClipper) => oldClipper.radius != radius;
}
