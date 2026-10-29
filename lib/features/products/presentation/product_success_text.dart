import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/product_tax_label.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';
import 'package:orange_one/l10n/l10n.dart';

/// The success toast of an edit: its title and text name only [fields], the
/// fields that were changed and saved, with their new values from [product].
({String title, String message}) editSuccessText(
  AppLocalizations l10n,
  ProductDetails product,
  Set<ProductEditField> fields,
) {
  // Fixed order, whatever the order the fields were changed in.
  final ordered = ProductEditField.values.where(fields.contains).toList();
  final combination = ordered.isEmpty
      ? 'other'
      : ordered
            .skip(1)
            .fold(
              ordered.first.name,
              (text, field) => text + _capitalized(field.name),
            );
  return (
    title: l10n.editSuccessTitle(combination),
    message: [
      for (final field in ordered)
        switch (field) {
          ProductEditField.name => l10n.editSuccessName(product.name),
          ProductEditField.tax => l10n.editSuccessTax(
            localizedTaxText(l10n, product),
          ),
          ProductEditField.category => l10n.editSuccessCategory(
            product.category?.name ?? l10n.categoryNone,
          ),
        },
    ].join(' \u00b7 '),
  );
}

String _capitalized(String text) =>
    '${text[0].toUpperCase()}${text.substring(1)}';
