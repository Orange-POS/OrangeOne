import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/app_logo.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

class ProductNameCard extends StatelessWidget {
  const new({
    required this.product,
    this.emptyTitle = 'Product Not Found',
    super.key,
  });
  final ProductDetails? product;
  final String emptyTitle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    decoration: const BoxDecoration(gradient: OrangeTheme.homeGradient),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: OrangeTheme.gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: .5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, 4),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(),
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
}
