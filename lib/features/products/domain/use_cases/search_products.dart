import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

/// Product search by name, barcode or internal reference, cursor paginated.
class SearchProducts {
  const new(this.repository);
  final ProductDetailsRepository repository;

  Future<ProductPage> call({
    String? query,
    int? categoryId,
    String? cursor,
    int limit = 25,
  }) {
    final text = query?.trim();
    if (text != null &&
        text.isNotEmpty &&
        (text.length < 2 || text.length > 64)) {
      throw const FormatException('Enter 2–64 characters to search.');
    }
    if ((categoryId != null && categoryId <= 0) || limit < 1 || limit > 100) {
      throw const FormatException('Enter a valid product search.');
    }
    return repository.searchProducts(
      query: text == null || text.isEmpty ? null : text,
      categoryId: categoryId,
      cursor: cursor,
      limit: limit,
    );
  }
}
