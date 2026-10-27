import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/shared/widgets/app_logo.dart';
import 'package:orange_one/shared/widgets/product_sync_indicator.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

class ProductNameCard extends StatelessWidget {
  const new({
    required this.product,
    this.emptyTitle = 'Product Not Found',
    this.detailsLayout = false,
    this.onEdit,
    this.onAdjustStock,
    super.key,
  });
  final ProductDetails? product;
  final String emptyTitle;
  final bool detailsLayout;
  final VoidCallback? onEdit;

  /// Opens Update Stock; null keeps the stock action disabled.
  final VoidCallback? onAdjustStock;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(16, 0, 16, detailsLayout ? 16 : 24),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: .5),
      ),
      child: detailsLayout
          ? _detailsContent()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(),
                    const Spacer(),
                    ProductSyncIndicator(barcode: product?.barcode),
                  ],
                ),
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
  Widget _detailsContent() => Column(
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
          const SizedBox(width: 10),
          _pencil(
            'Edit product name',
            'assets/icons/product_detail_name_edit.svg',
            onEdit,
          ),
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
                  quantity: product?.stock,
                  unit: product?.unit ?? '',
                  compact: true,
                ),
              ],
            ),
          ),
          _pencil(
            'Update stock',
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
            const Text(
              'Barcode',
              style: TextStyle(
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
