import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/use_cases/adjust_stock.dart';
import 'package:orange_one/l10n/l10n.dart';
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
      Text(
        context.l10n.stockCountedLabel,
        style: const TextStyle(fontWeight: FontWeight.w500),
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
          hintText: context.l10n.stockCountedHint,
          helperText: context.l10n.stockCountedHelper,
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
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.stockConfirmTitle),
      content: Text(
        l10n.stockConfirmMessage(
          product.name,
          stockQuantityLabel(current, product.unit),
          stockQuantityLabel(counted, product.unit),
          '$sign$change',
        ),
      ),
      actions: [
        TextButton(
          onPressed: _answered ? null : () => _answer(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _answered ? null : () => _answer(true),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
