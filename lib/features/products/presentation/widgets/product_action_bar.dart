import 'package:flutter/material.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';

/// Fixed, safe-area-aware actions; the page body scrolls independently.
class ProductActionBar extends StatelessWidget {
  const new({required this.onUpdatePrice, this.offline = false, super.key});
  final VoidCallback? onUpdatePrice;
  final bool offline;

  @override
  Widget build(BuildContext context) => ProductActionSurface(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final price = FilledButton(
          onPressed: onUpdatePrice,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Update Price'),
        );
        final stock = OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Update Stock'),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxWidth >= 600)
              Row(
                children: [
                  Expanded(child: price),
                  const SizedBox(width: 12),
                  Expanded(child: stock),
                ],
              )
            else ...[
              price,
              const SizedBox(height: 8),
              stock,
            ],
            const SizedBox(height: 8),
            Text(
              offline
                  ? 'Offline: read-only. Reconnect to update products.'
                  : 'Stock updates are not supported by the current server.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5F6368)),
            ),
          ],
        );
      },
    ),
  );
}
