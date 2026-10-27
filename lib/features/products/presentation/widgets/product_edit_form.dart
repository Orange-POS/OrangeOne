import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductEditForm extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.enabled,
    required this.taxLabel,
    required this.onSelectTax,
    this.categoryLabel,
    this.onSelectCategory,
    this.error,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String taxLabel;
  final VoidCallback? onSelectTax;

  /// The category field is shown only when a label is supplied.
  final String? categoryLabel;
  final VoidCallback? onSelectCategory;
  final String? error;

  InputDecoration _decoration() => InputDecoration(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    filled: !enabled,
    fillColor: const Color(0xFFF5F6F8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDADCE0)),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDADCE0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OrangeTheme.scannerAccent, width: 2),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Product Name'),
      const SizedBox(height: 8),
      TextField(
        key: const Key('product-name-input'),
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.sentences,
        decoration: _decoration().copyWith(errorText: error, errorMaxLines: 3),
      ),
      const SizedBox(height: 16),
      const Text('TAX'),
      const SizedBox(height: 8),
      Semantics(
        button: true,
        label: 'Select product tax',
        child: InkWell(
          key: const Key('product-tax-input'),
          onTap: onSelectTax,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: _decoration().copyWith(
              enabled: onSelectTax != null,
              suffixIcon: const Icon(Icons.expand_more),
            ),
            child: Text(
              taxLabel.isEmpty ? 'Tax information unavailable' : taxLabel,
            ),
          ),
        ),
      ),
      if (categoryLabel case final category?) ...[
        const SizedBox(height: 16),
        const Text('CATEGORY'),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: 'Select product category',
          child: InkWell(
            key: const Key('product-category-input'),
            onTap: onSelectCategory,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: _decoration().copyWith(
                enabled: onSelectCategory != null,
                suffixIcon: const Icon(Icons.expand_more),
              ),
              child: Text(category),
            ),
          ),
        ),
      ],
    ],
  );
}
