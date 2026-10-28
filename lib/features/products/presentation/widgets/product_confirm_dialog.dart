import 'package:flutter/material.dart';
import 'package:orange_one/l10n/l10n.dart';

/// The confirmation popup of the product forms (same design as the price and
/// stock confirmations). Pops `true` only when Confirm is selected.
class ProductConfirmDialog extends StatefulWidget {
  const new({required this.title, required this.message, super.key});
  final String title;
  final String message;
  @override
  State<ProductConfirmDialog> createState() => _ProductConfirmDialogState();
}

class _ProductConfirmDialogState extends State<ProductConfirmDialog> {
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
      title: Text(widget.title),
      content: Text(widget.message),
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
