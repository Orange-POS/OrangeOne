import 'package:flutter/material.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductCreationForm extends StatelessWidget {
  const new({
    required this.value,
    required this.name,
    required this.price,
    required this.nameFocus,
    required this.priceFocus,
    required this.onName,
    required this.onPrice,
    required this.onTax,
    super.key,
  });
  final ProductCreationState value;
  final TextEditingController name;
  final TextEditingController price;
  final FocusNode nameFocus;
  final FocusNode priceFocus;
  final ValueChanged<String> onName;
  final ValueChanged<String> onPrice;
  final VoidCallback? onTax;

  InputDecoration _decoration() => InputDecoration(
    contentPadding: const EdgeInsets.all(16),
    filled: !value.editable,
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
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Product Name'),
      const SizedBox(height: 8),
      TextField(
        key: const Key('create-product-name'),
        controller: name,
        focusNode: nameFocus,
        enabled: value.editable,
        onChanged: onName,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => priceFocus.requestFocus(),
        decoration: _decoration().copyWith(
          hintText: 'Enter product name',
          errorText: value.nameError,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 16),
      PriceUpdateForm(
        alwaysShowCurrency: true,
        controller: price,
        focusNode: priceFocus,
        onChanged: onPrice,
        enabled: value.editable,
        error: value.priceError,
      ),
      const SizedBox(height: 16),
      const Text('TAX'),
      const SizedBox(height: 8),
      Semantics(
        button: true,
        label: 'Select product tax',
        child: InkWell(
          key: const Key('create-product-tax'),
          onTap: onTax,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: _decoration().copyWith(
              suffixIcon: const Icon(Icons.expand_more),
            ),
            child: Text(value.taxLabel),
          ),
        ),
      ),
    ],
  );
}
