import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

class CreateProduct {
  const new(this.repository);
  final ProductDetailsRepository repository;

  NewProduct validate({
    required String barcode,
    required String name,
    required String price,
    required List<int>? taxIds,
    required ProductCreationContext context,
    int? categoryId,
    String stock = '',
  }) {
    if (!context.canCreate) {
      throw const FormatException('Product creation is not available.');
    }
    if (taxIds == null ||
        taxIds.any((id) => !context.taxes.any((tax) => tax.id == id))) {
      throw const FormatException('Select a tax option, including No Tax.');
    }
    if (categoryId == null ||
        !context.categories.any((category) => category.id == categoryId)) {
      throw const FormatException('Select a category.');
    }
    return NewProduct(
      barcode: NewProduct.validateBarcode(barcode),
      name: NewProduct.validateName(name),
      // An empty price is 0.00; it is still a deliberate, valid price.
      price: ChfPrice.parse(price.trim().isEmpty ? '0.00' : price),
      taxIds: List.unmodifiable(taxIds),
      categoryId: categoryId,
      initialQuantity: stock.trim().isEmpty ? null : StockCount.parse(stock),
    );
  }

  Future<ProductDetails> call(NewProduct product) =>
      repository.createProduct(product);
}
