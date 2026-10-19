import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

class ProductResultPanel extends StatelessWidget {
  const new({
    required this.state,
    required this.onScanAgain,
    required this.onRetry,
    required this.onAddProduct,
    super.key,
  });
  final AsyncValue<ProductLookup?> state;
  final VoidCallback onScanAgain;
  final VoidCallback onRetry;
  final ValueChanged<String> onAddProduct;

  @override
  Widget build(BuildContext context) {
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
                const Text(
                  'Last scanned',
                  style: TextStyle(color: OrangeTheme.secondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (state.isLoading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Text('Looking up product…')),
                    ],
                  )
                else if (state.hasError) ...[
                  Text(
                    error is AppFailure
                        ? error.message
                        : 'Unable to look up this product.',
                  ),
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
                          child: const Text('Retry lookup'),
                        ),
                      TextButton(
                        onPressed: onScanAgain,
                        child: const Text('Scan another barcode'),
                      ),
                    ],
                  ),
                ] else if (product != null) ...[
                  Container(
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
                                StockBadge(
                                  quantity: product.stockQuantity,
                                  unit: product.unit,
                                  onLightSurface: true,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 20,
                                  children: [
                                    Text(
                                      product.barcode,
                                      style: const TextStyle(
                                        color: OrangeTheme.secondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      product.price.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
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
                  ),
                ] else if (lookup != null) ...[
                  const Text(
                    'Product not found',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text('No POS product matches barcode ${lookup.barcode}.'),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () => onAddProduct(lookup.barcode),
                        child: const Text('Add product'),
                      ),
                      TextButton(
                        onPressed: onScanAgain,
                        child: const Text('Scan another barcode'),
                      ),
                    ],
                  ),
                ] else
                  const Text('Scan a product barcode to look it up.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
