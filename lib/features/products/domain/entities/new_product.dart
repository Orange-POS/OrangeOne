import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';

class NewProduct {
  const new({
    required this.barcode,
    required this.name,
    required this.price,
    required this.taxIds,
  });
  final String barcode;
  final String name;
  final ChfPrice price;
  final List<int> taxIds;

  static String validateBarcode(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        value.length > 256 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      throw const FormatException('A valid scanned barcode is required.');
    }
    return value;
  }

  static String validateName(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        value.length > 128 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      throw const FormatException('Enter a product name of 1–128 characters.');
    }
    return value;
  }
}

class ProductCreationContext {
  const new({
    required this.details,
    required this.taxes,
    required this.supportsCreateOnly,
  });
  final ProductDetailsState details;
  final List<ProductTax> taxes;

  /// Creation never upserts (`POST /products`); kept for existing callers.
  final bool supportsCreateOnly;

  /// `POST /products` requires product creation and price permissions; tax
  /// options must be readable for the explicit tax choice.
  bool get permitted =>
      details.access.createProduct &&
      details.access.updatePrice &&
      details.access.readReferences;
  bool get canCreate => permitted && details.product == null;
}
