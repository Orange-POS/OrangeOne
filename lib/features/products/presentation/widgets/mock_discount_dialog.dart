import 'package:flutter/material.dart';

typedef MockDiscount = ({String name, String percent});

class MockDiscountDialog extends StatefulWidget {
  const new({required this.initial, super.key});
  final MockDiscount initial;
  @override
  State<MockDiscountDialog> createState() => _MockDiscountDialogState();
}

class _MockDiscountDialogState extends State<MockDiscountDialog> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _percent = TextEditingController(text: widget.initial.percent);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit mock discount'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Preview only. This does not change product prices.'),
            TextFormField(
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Offer name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an offer name.'
                  : null,
            ),
            TextFormField(
              controller: _percent,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Discount percent'),
              validator: (value) {
                final number = double.tryParse(value ?? '');
                return number == null ||
                        !number.isFinite ||
                        number < 0 ||
                        number > 100
                    ? 'Enter a percentage from 0 to 100.'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              name: _name.text.trim(),
              percent: _percent.text.trim(),
            ));
          }
        },
        child: const Text('Apply mock discount'),
      ),
    ],
  );
}
