import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/use_cases/adjust_stock.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Quantity text without insignificant zeros (`48`, `12.5`) plus the unit.
String stockQuantityLabel(double quantity, String unit) {
  var text = quantity.toStringAsFixed(6);
  text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return unit.isEmpty ? text : '$text $unit';
}

/// The localized reason a stock quantity cannot be submitted.
String stockInputMessage(
  AppLocalizations l10n,
  StockInputException error, {
  required double? current,
  required String unit,
}) => switch (error.issue) {
  StockInputIssue.invalid => l10n.stockErrorInvalid,
  StockInputIssue.wholeNumber => l10n.stockErrorWhole,
  StockInputIssue.decimals => l10n.stockErrorDecimals(error.decimals ?? 0),
  StockInputIssue.zero => l10n.stockErrorZero,
  StockInputIssue.exceedsStock => l10n.stockErrorExceeds(
    stockQuantityLabel(current ?? 0, unit),
  ),
  StockInputIssue.unavailable => l10n.stockCannotCount,
};

/// The quantity text without the unit (`150`, `12.5`) for the preview.
String _plain(double quantity) => stockQuantityLabel(quantity, '');

/// The entered quantity of the selected operation: the counted stock for
/// Update, the quantity to add or to remove otherwise, with a live preview of
/// the stock that results.
class StockCountForm extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.enabled,
    this.operation = StockOperation.update,
    this.unit = '',
    this.error,
    this.current,
    this.preview,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final StockOperation operation;
  final String unit;
  final StockInputException? error;

  /// The stock on hand and the stock after the entered quantity (valid input).
  final double? current;
  final double? preview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, hint, helper) = switch (operation) {
      StockOperation.update => (
        l10n.stockCountedLabel,
        l10n.stockCountedHint,
        l10n.stockCountedHelper,
      ),
      StockOperation.add => (
        l10n.stockAddLabel,
        l10n.stockAddHint,
        l10n.stockAddHelper,
      ),
      StockOperation.remove => (
        l10n.stockRemoveLabel,
        l10n.stockRemoveHint,
        l10n.stockRemoveHelper,
      ),
    };
    final result = preview;
    final amount = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    final resultText = result == null ? null : stockQuantityLabel(result, unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _field(
          context,
          hint,
          helper,
          error == null
              ? null
              : stockInputMessage(l10n, error!, current: current, unit: unit),
        ),
        if (resultText != null && amount != null && current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              key: const Key('stock-preview'),
              switch (operation) {
                StockOperation.update => l10n.stockPreviewUpdate(resultText),
                StockOperation.add => l10n.stockPreviewAdd(
                  _plain(current!),
                  _plain(amount),
                  resultText,
                ),
                StockOperation.remove => l10n.stockPreviewRemove(
                  _plain(current!),
                  _plain(amount),
                  resultText,
                ),
              },
              style: const TextStyle(
                color: Color(0xFF188038),
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    String hint,
    String helper,
    String? errorText,
  ) => TextField(
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
      hintText: hint,
      helperText: helper,
      errorText: errorText,
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
    final amount = widget.confirmation.count.quantity;
    final counted = widget.confirmation.expectedStock;
    final difference = counted - current;
    final sign = difference > 0
        ? '+'
        : difference < 0
        ? '-'
        : '';
    final change = stockQuantityLabel(difference.abs(), product.unit);
    final l10n = context.l10n;
    final currentText = stockQuantityLabel(current, product.unit);
    final amountText = stockQuantityLabel(amount, product.unit);
    final resultText = stockQuantityLabel(counted, product.unit);
    return AlertDialog(
      title: Text(l10n.stockConfirmTitle),
      content: Text(switch (widget.confirmation.operation) {
        StockOperation.update => l10n.stockConfirmMessage(
          product.name,
          currentText,
          resultText,
          '$sign$change',
        ),
        StockOperation.add => l10n.stockConfirmAddMessage(
          product.name,
          currentText,
          amountText,
          resultText,
        ),
        StockOperation.remove => l10n.stockConfirmRemoveMessage(
          product.name,
          currentText,
          amountText,
          resultText,
        ),
      }),
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
