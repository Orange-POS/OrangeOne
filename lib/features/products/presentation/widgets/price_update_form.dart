import 'package:flutter/material.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/validation_haptic.dart';

class PriceUpdateForm extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.enabled,
    this.error,
    this.alwaysShowCurrency = false,
    this.label,
    this.hint,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? error;
  final bool alwaysShowCurrency;

  /// Defaults to the New Price texts.
  final String? label;
  final String? hint;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label ?? context.l10n.priceNewLabel,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      ValidationHaptic(
        error: error,
        child: TextField(
          key: const Key('new-price-input'),
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => focusNode.unfocus(),
          decoration: OrangeTheme.productInput(enabled: enabled).copyWith(
            prefixText: alwaysShowCurrency ? null : 'CHF ',
            prefixIcon: alwaysShowCurrency
                ? const Padding(
                    padding: EdgeInsets.only(left: 16, right: 8),
                    child: Text(
                      'CHF',
                      style: TextStyle(color: OrangeTheme.secondary),
                    ),
                  )
                : null,
            prefixIconConstraints: alwaysShowCurrency
                ? const BoxConstraints()
                : null,
            hintText: hint ?? context.l10n.priceNewHint,
            errorText: error,
            errorMaxLines: 3,
          ),
        ),
      ),
    ],
  );
}
