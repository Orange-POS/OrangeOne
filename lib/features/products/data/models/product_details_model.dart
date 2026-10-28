import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/data/models/product_reference_model.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';

abstract final class ProductDetailsModel {
  static ProductDetails parse(Map<String, dynamic> json, String barcode) {
    final id = json['id'];
    final name = json['name'];
    final price = json['price'];
    final stock = json['stock_quantity'];
    if (id is! int ||
        id <= 0 ||
        name is! String ||
        name.trim().isEmpty ||
        json['barcode'] != barcode ||
        price is! num ||
        !price.isFinite ||
        (stock != null && (stock is! num || !stock.isFinite))) {
      throw invalidResponse;
    }
    final taxes = <String>[];
    final taxIds = <int>[];
    var completeIds = true;
    final rawTaxes = json['taxes'];
    if (rawTaxes != null && rawTaxes != false) {
      if (rawTaxes is! List) throw invalidResponse;
      for (final tax in rawTaxes) {
        if (tax is! Map<String, dynamic> ||
            tax['name'] is! String ||
            tax['amount'] is! num ||
            !(tax['amount'] as num).isFinite ||
            tax['amount_type'] is! String) {
          throw invalidResponse;
        }
        final amount = tax['amount'] as num;
        final taxId = tax['id'];
        if (taxId is int && taxId > 0) {
          taxIds.add(taxId);
        } else {
          completeIds = false;
        }
        taxes.add(
          tax['amount_type'] == 'percent'
              ? ProductReferenceModel.taxLabel(tax['name'] as String, amount)
              : tax['name'] as String,
        );
      }
    }
    return ProductDetails(
      id: id,
      name: name,
      barcode: barcode,
      price: price.toDouble(),
      stock: (stock as num?)?.toDouble(),
      unit: _text(json['uom']),
      reference: _text(json['default_code']),
      taxes: List.unmodifiable(taxes),
      taxIds: rawTaxes is List && completeIds
          ? List.unmodifiable(taxIds)
          : null,
      currency: _optionalText(json['currency']),
      category: _category(json['category']),
      description: _optionalText(json['description']),
      version: _optionalText(json['version']),
      stockAdjustable: json['stock_adjustable'] == true,
      stockLocationId: _optionalId(json['stock_location_id']),
      quantityDecimals: _decimals(json['uom_rounding']),
    );
  }

  static int? _optionalId(Object? value) {
    if (value == null) return null;
    if (value is! int || value <= 0) throw invalidResponse;
    return value;
  }

  /// Decimal places allowed by the unit rounding (`"0.01"` → 2, `"1"` → 0).
  static int? _decimals(Object? rounding) {
    if (rounding == null) return null;
    if (rounding is! String ||
        !RegExp(r'^\d{1,12}(\.\d{1,6})?$').hasMatch(rounding)) {
      throw invalidResponse;
    }
    final fraction = rounding.split('.').elementAtOrNull(1) ?? '';
    return fraction.replaceFirst(RegExp(r'0+$'), '').length;
  }

  /// Mobile API v2 fields of a product read record (absent offline).
  static String? _optionalText(Object? value) {
    if (value == null) return null;
    if (value is! String) throw invalidResponse;
    return value;
  }

  static ProductCategory? _category(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic> ||
        value['id'] is! int ||
        value['name'] is! String) {
      throw invalidResponse;
    }
    return ProductCategory(
      id: value['id'] as int,
      name: value['name'] as String,
    );
  }

  static String _text(Object? value) {
    if (value == null || value == false) return '';
    if (value is! String) throw invalidResponse;
    return value;
  }
}
