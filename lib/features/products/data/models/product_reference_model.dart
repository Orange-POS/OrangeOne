import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';

/// Maps `GET /taxes` and `GET /categories` data to picker options.
abstract final class ProductReferenceModel {
  static final _amount = RegExp(r'^-?\d{1,12}(\.\d{1,6})?$');

  /// "VAT (15%)"; a name that already states the rate stays as it is, so
  /// "15%" is shown once.
  static String taxLabel(String name, Object amount) {
    final number = amount is num ? amount : num.tryParse('$amount');
    if (number == null) return name;
    final rate = number == number.roundToDouble()
        ? number.round().toString()
        : number.toString().replaceFirst(RegExp(r'0+$'), '');
    final compact = name.replaceAll(RegExp(r'\s'), '');
    return compact.contains('$rate%') ? name : '$name ($rate%)';
  }

  /// Default taxes of `GET /taxes`; ids that are not offered are ignored.
  static List<int> defaultTaxIds(Object? data) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final raw = data['default_tax_ids'];
    if (raw == null) return const [];
    if (raw is! List || raw.any((id) => id is! int || id <= 0)) {
      throw invalidResponse;
    }
    return List.unmodifiable(raw.cast<int>());
  }

  /// The category returned by `POST /categories`.
  static ProductCategory category(Object? data) {
    if (data is! Map<String, dynamic> ||
        data['id'] is! int ||
        (data['id'] as int) <= 0 ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty) {
      throw invalidResponse;
    }
    return ProductCategory(
      id: data['id'] as int,
      name: (data['name'] as String).trim(),
    );
  }

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
      label: type == 'percent' ? taxLabel(name, amount) : name,
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
