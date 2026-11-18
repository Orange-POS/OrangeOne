import 'package:flutter/material.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/l10n/l10n.dart';

/// The confirmation popup before every write (product forms, price, stock,
/// discounts). It pops `true` only for Confirm, answers once (a second tap
/// while it closes is ignored) and plays the confirm haptic.
class ConfirmDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.message,
    this.confirmLabel,
    this.confirmKey,
    this.outlinedCancel = false,
    super.key,
  });

  final String title;
  final String message;

  /// The confirm button's text; Confirm when null.
  final String? confirmLabel;
  final Key? confirmKey;

  /// Cancel as an outlined button (the discount screens' design) instead of
  /// a text button (the product forms').
  final bool outlinedCancel;

  /// Shows the dialog; false when it is cancelled or dismissed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    Key? confirmKey,
    bool outlinedCancel = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => ConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          confirmKey: confirmKey,
          outlinedCancel: outlinedCancel,
        ),
      ) ??
      false;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool _answered = false;

  void _answer(bool accepted) {
    if (_answered) return;
    setState(() => _answered = true);
    if (accepted) playHaptic(context, HapticEffect.confirm);
    Navigator.pop(context, accepted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cancel = _answered ? null : () => _answer(false);
    final cancelText = Text(l10n.commonCancel);
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
        if (widget.outlinedCancel)
          OutlinedButton(onPressed: cancel, child: cancelText)
        else
          TextButton(onPressed: cancel, child: cancelText),
        FilledButton(
          key: widget.confirmKey,
          onPressed: _answered ? null : () => _answer(true),
          child: Text(widget.confirmLabel ?? l10n.commonConfirm),
        ),
      ],
    );
  }
}
