import 'package:orange_one/features/products/domain/entities/product_details.dart';

/// A missing assignment must never be presented as confirmed tax-free data.
extension ProductTaxLabel on ProductDetails {
  String get currentTaxLabel {
    if (taxes.isNotEmpty) return taxes.join(', ');
    return taxIds?.isEmpty == true
        ? 'No taxes assigned'
        : 'Tax information unavailable';
  }
}
