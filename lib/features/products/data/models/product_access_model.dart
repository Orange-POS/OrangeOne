import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';

/// Maps the Mobile API `Permissions` object (all keys are booleans).
abstract final class ProductAccessModel {
  static ProductAccess parse(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.values.any((permission) => permission is! bool)) {
      throw invalidResponse;
    }
    bool granted(String key) => value[key] == true;
    return ProductAccess(
      editName: granted('product_update_name'),
      updatePrice: granted('product_update_price'),
      readReferences: granted('product_read'),
      updateTaxes: granted('product_update_taxes'),
      updateCategory: granted('product_update_category'),
      createProduct: granted('product_create'),
      adjustStock: granted('stock_adjust'),
      readHistory: granted('product_history_read'),
    );
  }
}
