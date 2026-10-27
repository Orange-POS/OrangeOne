import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class PriceChangeConfirmation {
  const new({required this.product, required this.price});
  final ProductDetails product;
  final ChfPrice price;
}

class UpdateProductPrice {
  const new(this.repository);
  final ProductDetailsRepository repository;

  ChfPrice validate(String raw, ProductDetails product) {
    final price = ChfPrice.parse(raw);
    if (price.formatted == product.price.toStringAsFixed(2)) {
      throw const FormatException('Enter a different price.');
    }
    return price;
  }

  Future<ProductDetails> call(PriceChangeConfirmation confirmation) =>
      repository.updatePrice(confirmation.product, confirmation.price);
}
