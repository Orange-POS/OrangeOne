import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';

/// Maps `GET /taxes` and `GET /categories` data to picker options.
abstract final class ProductReferenceModel {
  static final _amount = RegExp(r'^-?\d{1,12}(\.\d{1,6})?$');

  static List<ProductTax> taxes(Object? data) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final raw = data['taxes'];
    if (raw is! List) throw invalidResponse;
    final ids = <int>{};
    return List.unmodifiable([for (final item in raw) _tax(item, ids)]);
  }

  static ProductTax _tax(Object? item, Set<int> ids) {
    if (item is! Map<String, dynamic>) throw invalidResponse;
    final id = item['id'];
    final name = item['name'];
    final amount = item['amount'];
    final type = item['amount_type'];
    if (id is! int ||
        id <= 0 ||
        !ids.add(id) ||
        name is! String ||
        name.trim().isEmpty ||
        amount is! String ||
        !_amount.hasMatch(amount) ||
        type is! String) {
      throw invalidResponse;
    }
    return ProductTax(
      id: id,
      label: type == 'percent' ? '$name ($amount%)' : name,
    );
  }

  static List<ProductCategory> categories(Object? data) {
    if (data is! List) throw invalidResponse;
    final ids = <int>{};
    return List.unmodifiable([
      for (final item in data)
        if (item is Map<String, dynamic> &&
            item['id'] is int &&
            (item['id'] as int) > 0 &&
            ids.add(item['id'] as int) &&
            item['name'] is String &&
            (item['name'] as String).trim().isNotEmpty)
          ProductCategory(id: item['id'] as int, name: item['name'] as String)
        else
          throw invalidResponse,
    ]);
  }
}
