import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';

class NewProduct {
  const new({
    required this.barcode,
    required this.name,
    required this.price,
    required this.taxIds,
    this.categoryId,
    this.initialQuantity,
  });
  final String barcode;
  final String name;
  final ChfPrice price;
  final List<int> taxIds;
  final int? categoryId;

  /// Null when the user did not enter a stock quantity: it is then not sent
  /// and never treated as zero.
  final StockCount? initialQuantity;

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
    this.defaultTaxIds = const [],
    this.categories = const [],
  });
  final ProductDetailsState details;
  final List<ProductTax> taxes;

  /// The backend's configured default taxes (`default_tax_ids`).
  final List<int> defaultTaxIds;
  final List<ProductCategory> categories;

  /// Default taxes that are offered, or null when none is configured.
  List<int>? get initialTaxIds {
    final ids = [
      for (final id in defaultTaxIds)
        if (taxes.any((tax) => tax.id == id)) id,
    ];
    return ids.isEmpty ? null : List.unmodifiable(ids);
  }

  /// `POST /products` requires product creation and price permissions; tax
  /// options must be readable for the explicit tax choice.
  bool get permitted =>
      details.access.createProduct &&
      details.access.updatePrice &&
      details.access.readReferences;
  bool get canCreate => permitted && details.product == null;
}
