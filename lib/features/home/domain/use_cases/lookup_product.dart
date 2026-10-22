import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';

class LookupProduct {
  const new(this._repository);
  final ProductRepository _repository;

  static String validate(String raw) {
    // Preserve leading zeros and case; Odoo performs an exact string match.
    final barcode = raw.trim();
    if (barcode.isEmpty ||
        barcode.length > 256 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(barcode)) {
      throw const FormatException('Invalid product barcode.');
    }
    return barcode;
  }

  Future<Product?> call(String raw, {bool refresh = false}) =>
      _repository.findByBarcode(validate(raw), refresh: refresh);
}
