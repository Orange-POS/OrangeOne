import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/use_cases/adjust_stock.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Quantity text without insignificant zeros (`48`, `12.5`) plus the unit.
String stockQuantityLabel(double quantity, String unit) {
  var text = quantity.toStringAsFixed(6);
  text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return unit.isEmpty ? text : '$text $unit';
}

/// The counted on-hand quantity; it replaces the current stock.
class StockCountForm extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.enabled,
    this.unit = '',
    this.error,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String unit;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Counted Quantity',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('stock-count-input'),
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => focusNode.unfocus(),
        decoration: InputDecoration(
          suffixText: unit.isEmpty ? null : unit,
          hintText: 'Enter the counted quantity',
          helperText: 'Replaces the current stock at the POS location.',
          errorText: error,
          errorMaxLines: 3,
          filled: !enabled,
          fillColor: const Color(0xFFF5F6F8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDADCE0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: OrangeTheme.brand, width: 2),
          ),
        ),
      ),
    ],
  );
}

class StockCountDialog extends StatefulWidget {
  const new({required this.confirmation, super.key});
  final StockCountConfirmation confirmation;
  @override
  State<StockCountDialog> createState() => _StockCountDialogState();
}

class _StockCountDialogState extends State<StockCountDialog> {
  bool _answered = false;
  void _answer(bool accepted) {
    if (_answered) return;
    setState(() => _answered = true);
    Navigator.pop(context, accepted);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.confirmation.product;
    final current = product.stock ?? 0;
    final counted = widget.confirmation.count.quantity;
    final difference = counted - current;
    final sign = difference > 0
        ? '+'
        : difference < 0
        ? '-'
        : '';
    final change = stockQuantityLabel(difference.abs(), product.unit);
    return AlertDialog(
      title: const Text('Confirm stock update'),
      content: Text(
        '${product.name}\n\n'
        'Current stock: ${stockQuantityLabel(current, product.unit)}\n'
        'Counted stock: ${stockQuantityLabel(counted, product.unit)}\n'
        'Difference: $sign$change\n\n'
        'Save this count to Odoo?',
      ),
      actions: [
        TextButton(
          onPressed: _answered ? null : () => _answer(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _answered ? null : () => _answer(true),
          child: const Text('Confirm update'),
        ),
      ],
    );
  }
}
