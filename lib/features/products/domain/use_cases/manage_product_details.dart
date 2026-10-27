import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class ManageProductDetails {
  const new(this.repository);
  final ProductDetailsRepository repository;

  Future<ProductDetailsState> load(String raw) {
    final barcode = raw.trim();
    if (barcode.isEmpty ||
        barcode.length > 256 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(barcode)) {
      throw const FormatException('Enter a valid product barcode.');
    }
    return repository.load(barcode);
  }

  Future<ProductDetails> rename(ProductDetails product, String value) {
    final name = value.trim();
    if (product.id <= 0 || name.isEmpty || name.length > 128) {
      throw const FormatException('Enter a product name of 1–128 characters.');
    }
    return repository.updateName(product, name);
  }

  Future<ProductDetails> reprice(ProductDetails product, String value) {
    final price = ChfPrice.parse(value);
    if (product.id <= 0) {
      throw const FormatException('Enter a valid non-negative price.');
    }
    return repository.updatePrice(product, price);
  }
}
