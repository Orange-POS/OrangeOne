import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/product_payload.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';

/// Maps a `GET /products` page (`ProductSummary` list and `next_cursor`).
abstract final class ProductSummaryModel {
  static ProductPage page(Object? data, Map<String, dynamic> meta) {
    if (data is! List) throw invalidResponse;
    final cursor = meta['next_cursor'];
    if (cursor != null && cursor is! String) throw invalidResponse;
    return ProductPage(
      List.unmodifiable([
        for (final item in data) _summary(ProductPayload.summaryRecord(item)),
      ]),
      cursor as String?,
    );
  }

  static ProductSummary _summary(Map<String, dynamic> record) => ProductSummary(
    id: record['id'] as int,
    name: record['name'] as String,
    barcode: record['barcode'] as String?,
    price: record['price'] as double,
    currency: record['currency'] as String,
    stock: record['stock_quantity'] as double?,
  );
}
