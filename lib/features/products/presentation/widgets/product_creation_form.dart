import 'package:flutter/material.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductCreationForm extends StatelessWidget {
  const new({
    required this.value,
    required this.name,
    required this.price,
    required this.stock,
    required this.nameFocus,
    required this.priceFocus,
    required this.stockFocus,
    required this.onName,
    required this.onPrice,
    required this.onStock,
    required this.onTax,
    required this.onCategory,
    super.key,
  });
  final ProductCreationState value;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController stock;
  final FocusNode nameFocus;
  final FocusNode priceFocus;
  final FocusNode stockFocus;
  final ValueChanged<String> onName;
  final ValueChanged<String> onPrice;
  final ValueChanged<String> onStock;
  final VoidCallback? onTax;
  final VoidCallback? onCategory;

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

  Widget _selector({
    required Key key,
    required String semantics,
    required String text,
    required bool placeholder,
    required VoidCallback? onTap,
  }) => Semantics(
    button: true,
    label: semantics,
    child: InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decoration().copyWith(
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: Text(
          text,
          style: placeholder
              ? const TextStyle(color: OrangeTheme.secondary)
              : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final category = value.categoryName;
    final tax = value.taxText(l10n.taxNoTax);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.productNameLabel),
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
            hintText: l10n.createNameHint,
            errorText: value.nameError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.productCategoryLabel),
        const SizedBox(height: 8),
        _selector(
          key: const Key('create-product-category'),
          semantics: l10n.categorySelectSemantics,
          text: category ?? l10n.categorySelect,
          placeholder: category == null,
          onTap: onCategory,
        ),
        const SizedBox(height: 16),
        PriceUpdateForm(
          alwaysShowCurrency: true,
          controller: price,
          focusNode: priceFocus,
          onChanged: onPrice,
          enabled: value.editable,
          error: value.priceError,
          label: l10n.createPriceLabel,
          hint: l10n.createPriceHint,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.createStockLabel,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('create-product-stock'),
          controller: stock,
          focusNode: stockFocus,
          enabled: value.editable,
          onChanged: onStock,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => stockFocus.unfocus(),
          decoration: _decoration().copyWith(
            // Left empty, the stock is not set; it is not zero.
            hintText: l10n.stockNotSet,
            errorText: value.stockError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.productTaxLabel),
        const SizedBox(height: 8),
        _selector(
          key: const Key('create-product-tax'),
          semantics: l10n.taxSelectSemantics,
          text: tax ?? l10n.taxSelect,
          placeholder: tax == null,
          onTap: onTax,
        ),
      ],
    );
  }
}
