import 'package:flutter/material.dart';
import 'package:orange_one/core/errors/app_failure.dart';

class ProductEditDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.initialValue,
    required this.onSave,
    this.numeric = false,
    super.key,
  });
  final String title;
  final String initialValue;
  final bool numeric;
  final Future<void> Function(String) onSave;
  @override
  State<ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<ProductEditDialog> {
  late final _text = TextEditingController(text: widget.initialValue);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_text.text);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Unable to confirm the update. Refresh before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              enabled: !_busy,
              autofocus: true,
              maxLength: widget.numeric ? 24 : 200,
              keyboardType: widget.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: widget.numeric ? 'Price' : 'Product name',
              ),
            ),
            const Text('Confirm saves this change.'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Confirm update'),
        ),
      ],
    ),
  );
}
