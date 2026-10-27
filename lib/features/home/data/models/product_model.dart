import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';

abstract final class ProductModel {
  static Product fromJson(Map<String, dynamic> json, String scannedBarcode) {
    final id = json['id'];
    final name = json['name'];
    final barcode = json['barcode'];
    final price = json['price'];
    final stock = json['stock_quantity'];
    if (id is! int ||
        id <= 0 ||
        name is! String ||
        name.trim().isEmpty ||
        barcode != scannedBarcode ||
        price is! num ||
        !price.isFinite ||
        (stock != null && (stock is! num || !stock.isFinite))) {
      throw invalidResponse;
    }
    return Product(
      id: id,
      name: name,
      barcode: scannedBarcode,
      price: price.toDouble(),
      stockQuantity: (stock as num?)?.toDouble(),
      unit: _optionalText(json['uom']),
      reference: _optionalText(json['default_code']),
    );
  }

  static String _optionalText(Object? value) {
    if (value == null || value == false) return '';
    if (value is! String) throw invalidResponse;
    return value;
  }
}
