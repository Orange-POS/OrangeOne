import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/l10n/l10n.dart';

/// A missing assignment must never be presented as confirmed tax-free data.
extension ProductTaxLabel on ProductDetails {
  String get currentTaxLabel {
    if (taxes.isNotEmpty) return taxes.join(', ');
    return taxIds?.isEmpty == true
        ? 'No taxes assigned'
        : 'Tax information unavailable';
  }
}

/// The tax text of a product in the selected language.
String localizedTaxText(AppLocalizations l10n, ProductDetails product) =>
    product.taxes.isNotEmpty
    ? product.taxes.join(', ')
    : product.taxIds?.isEmpty == true
    ? l10n.detailsTaxNone
    : l10n.detailsTaxUnavailable;
