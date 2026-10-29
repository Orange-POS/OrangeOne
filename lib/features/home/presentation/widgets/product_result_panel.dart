import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/info_badge.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

/// The scanner's bottom card: the lookup in progress or its result and, while
/// idle, the latest scanned product (one card that each new scan replaces).
class ProductResultPanel extends StatelessWidget {
  const new({
    required this.state,
    required this.onScanAgain,
    required this.onRetry,
    required this.onAddProduct,
    this.recents = const [],
    this.onOpenRecent,
    super.key,
  });
  final AsyncValue<ProductLookup?> state;
  final VoidCallback onScanAgain;
  final VoidCallback onRetry;
  final ValueChanged<String> onAddProduct;

  /// Recently scanned products, newest first. Only the first is shown, while
  /// idle; the others stay in the history.
  final List<Product> recents;

  /// Looks the tapped recent product up again and opens it.
  final ValueChanged<String>? onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lookup = state.value;
    final product = lookup?.product;
    final error = state.error;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 16, 16, 34),
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.recentTitle,
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                if (state.isLoading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l10n.scannerLookingUp)),
                    ],
                  )
                else if (state.hasError) ...[
                  Text(error is AppFailure ? error.message : l10n.lookupFailed),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (error is AppFailure &&
                          {
                            FailureKind.network,
                            FailureKind.timeout,
                          }.contains(error.kind))
                        TextButton(
                          onPressed: onRetry,
                          child: Text(l10n.lookupRetry),
                        ),
                      TextButton(
                        onPressed: onScanAgain,
                        child: Text(l10n.scanAnother),
                      ),
                    ],
                  ),
                ] else if (product != null)
                  _ProductCard(product: product)
                else if (lookup != null) ...[
                  Text(
                    l10n.productNotFound,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(l10n.productNotFoundBody(lookup.barcode)),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () => onAddProduct(lookup.barcode),
                        child: Text(l10n.addProduct),
                      ),
                      TextButton(
                        onPressed: onScanAgain,
                        child: Text(l10n.scanAnother),
                      ),
                    ],
                  ),
                ] else if (recents.isEmpty)
                  Text(l10n.recentEmpty)
                else
                  _ProductCard(
                    key: Key('recent-${recents.first.barcode}'),
                    product: recents.first,
                    onTap: onOpenRecent == null
                        ? null
                        : () => onOpenRecent!(recents.first.barcode),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Name, stock, barcode and price of one product; tappable when [onTap] is set.
class _ProductCard extends StatelessWidget {
  const new({required this.product, this.onTap, super.key});
  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final category = product.category?.trim();
    final categoryText = category == null || category.isEmpty
        ? l10n.categoryNone
        : category;
    final card = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: OrangeTheme.pale,
        border: Border.all(color: const Color(0xFFDADCE0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: OrangeTheme.dark,
            child: Text(
              '✓',
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Category and barcode share the stock badge's design.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InfoBadge(
                        key: const Key('recent-category-badge'),
                        text: categoryText,
                        semanticsLabel: l10n.categoryLabel(categoryText),
                        onLightSurface: true,
                        singleLine: true,
                      ),
                      InfoBadge(
                        key: const Key('recent-barcode-badge'),
                        text: product.barcode,
                        semanticsLabel: l10n.barcodeLabel(product.barcode),
                        onLightSurface: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stockText(
                            product.stockQuantity,
                            product.unit,
                            StockBadgeLabels(
                              inStock: l10n.stockInStock,
                              outOfStock: l10n.stockOutOfStock,
                              unavailable: l10n.stockUnavailable,
                            ),
                          ),
                          style: const TextStyle(
                            color: OrangeTheme.secondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'CHF ${product.price.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: l10n.recentOpenSemantics(product.name, product.barcode),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }
}
