import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/app_logo.dart';
import 'package:orange_one/shared/widgets/info_badge.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

class ProductNameCard extends ConsumerWidget {
  const new({
    required this.product,
    this.emptyTitle = 'Product Not Found',
    this.detailsLayout = false,
    this.showActions = true,
    this.taxText,
    this.onEdit,
    this.onAdjustStock,
    super.key,
  });
  final ProductDetails? product;
  final String emptyTitle;
  final bool detailsLayout;

  /// Shows the pencil actions; the editing screens hide them.
  final bool showActions;

  /// The Tax badge shown with the stock badge on the editing screens; null
  /// keeps it hidden (Product Details never shows it).
  final String? taxText;
  final VoidCallback? onEdit;

  /// Opens Update Stock; null keeps the stock action disabled.
  final VoidCallback? onAdjustStock;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = product;
    // A product created without a stock quantity has no stock set yet, which
    // is not the same as a counted zero.
    final stockNotSet =
        current != null &&
        (current.stock ?? 0) == 0 &&
        ref.watch(unsetStockProvider).contains(current.barcode);
    return _card(context, stockNotSet);
  }

  Widget _card(BuildContext context, bool stockNotSet) => Container(
    padding: EdgeInsets.fromLTRB(16, 0, 16, detailsLayout ? 16 : 24),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: .5),
      ),
      child: detailsLayout
          ? _detailsContent(context, stockNotSet)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [AppLogo()]),
                const SizedBox(height: 16),
                Text(
                  product?.name ?? emptyTitle,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (product?.reference.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      product!.reference,
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                const SizedBox(height: 16),
                StockBadge(quantity: product?.stock, unit: product?.unit ?? ''),
              ],
            ),
    ),
  );
  Widget _detailsContent(BuildContext context, bool stockNotSet) {
    final l10n = context.l10n;
    final category = product?.category?.name.trim();
    final categoryText = category == null || category.isEmpty
        ? l10n.categoryNone
        : category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product?.name ?? emptyTitle,
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
              _pencil(
                l10n.detailsEditName,
                'assets/icons/product_detail_name_edit.svg',
                onEdit,
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
                spacing: 8,
                runSpacing: 8,
                children: [
                  // The category sits left of the stock, with the same design.
                  InfoBadge(
                    key: const Key('product-category-badge'),
                    text: categoryText,
                    semanticsLabel: l10n.categoryLabel(categoryText),
                    compact: true,
                    singleLine: true,
                  ),
                  StockBadge(
                    quantity: stockNotSet ? null : product?.stock,
                    unit: product?.unit ?? '',
                    compact: true,
                    labels: StockBadgeLabels(
                      inStock: l10n.stockInStock,
                      outOfStock: l10n.stockOutOfStock,
                      unavailable: stockNotSet
                          ? l10n.stockNotSet
                          : l10n.stockUnavailable,
                    ),
                  ),
                  if (taxText case final tax?)
                    InfoBadge(
                      key: const Key('product-tax-badge'),
                      text: tax,
                      semanticsLabel: l10n.detailsTax,
                      compact: true,
                      singleLine: true,
                    ),
                ],
              ),
            ),
            if (showActions)
              _pencil(
                l10n.detailsUpdateStock,
                'assets/icons/product_detail_stock_edit.svg',
                onAdjustStock,
              ),
          ],
        ),
        Container(
          key: const Key('product-hero-barcode'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/icons/product_barcode.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.detailsBarcode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product?.barcode ?? '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pencil(String tooltip, String asset, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: Opacity(
          opacity: onPressed == null ? .38 : 1,
          child: SvgPicture.asset(
            asset,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      );
}
