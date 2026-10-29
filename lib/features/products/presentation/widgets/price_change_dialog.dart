import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/use_cases/update_product_price.dart';
import 'package:orange_one/l10n/l10n.dart';

class PriceChangeDialog extends StatefulWidget {
  const new({required this.confirmation, super.key});
  final PriceChangeConfirmation confirmation;
  @override
  State<PriceChangeDialog> createState() => _PriceChangeDialogState();
}

class _PriceChangeDialogState extends State<PriceChangeDialog> {
  bool _answered = false;
  void _answer(bool accepted) {
    if (_answered) return;
    setState(() => _answered = true);
    Navigator.pop(context, accepted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.priceConfirmTitle),
      content: Text(
        l10n.priceConfirmMessage(
          widget.confirmation.product.name,
          widget.confirmation.product.price.toStringAsFixed(2),
          widget.confirmation.price.formatted,
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
