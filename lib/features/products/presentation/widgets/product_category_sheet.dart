import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductCategoryChoice {
  const new(this.id);
  final int? id;
}

/// Mirrors the tax sheet: selection is explicit, dismissing changes nothing.
class ProductCategorySheet extends StatelessWidget {
  const new({required this.categories, required this.selectedId, super.key});
  final List<ProductCategory> categories;
  final int? selectedId;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Select Category',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Close category selection',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.cancel_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _option(context, null, 'No category', selectedId == null),
          for (final category in categories)
            _option(
              context,
              category.id,
              category.name,
              selectedId == category.id,
            ),
        ],
      ),
    ),
  );

  Widget _option(BuildContext context, int? id, String label, bool selected) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF202124),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
          onPressed: () => Navigator.pop(context, ProductCategoryChoice(id)),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? OrangeTheme.scannerAccent
                    : const Color(0xFFDADCE0),
              ),
            ],
          ),
        ),
      );
}
