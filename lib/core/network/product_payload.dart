import 'package:orange_one/core/errors/app_failure.dart';

/// Mobile API v2 `Product` payloads, shared by the product features.
///
/// [productRecord] validates a payload and returns a *product read record*:
/// the field names the encrypted offline cache already stores (`price`,
/// `stock_quantity`, `uom`, `default_code`, `taxes`) plus v2-only fields the
/// cache does not persist (`currency`, `category`, `description`, `version`,
/// `permissions`, `stock_tracked`, `stock_adjustable`, `stock_location_id`,
/// `uom_rounding`). Offline reads
/// therefore keep working until the cache schema itself moves to v2, and
/// permissions and versions are never cached.
abstract final class ProductPayload {
  static final _barcode = RegExp(r'^[\x21-\x7E]{1,64}$');

  /// Barcodes accepted by `GET /products/by-barcode/{barcode}` and creation.
  static bool isApiBarcode(String barcode) =>
      _barcode.hasMatch(barcode) && barcode != '.' && barcode != '..';

  /// `/products/by-barcode/{barcode}` with the barcode safely encoded.
  static String byBarcodePath(String barcode) {
    if (!isApiBarcode(barcode)) {
      throw const AppFailure(
        FailureKind.validation,
        'Scan a valid product barcode.',
      );
    }
    return '/products/by-barcode/${Uri.encodeComponent(barcode)}';
  }

  static Map<String, dynamic> productRecord(Object? data) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final id = data['id'];
    final name = data['name'];
    final barcode = data['barcode'];
    final defaultCode = data['default_code'];
    final description = data['description'];
    final version = data['version'];
    final price = data['list_price'];
    final stock = data['stock'];
    final taxes = data['taxes'];
    final permissions = data['permissions'];
    if (id is! int ||
        id <= 0 ||
        name is! String ||
        name.trim().isEmpty ||
        (barcode != null && barcode is! String) ||
        (defaultCode != null && defaultCode is! String) ||
        (description != null && description is! String) ||
        version is! String ||
        version.isEmpty ||
        price is! Map<String, dynamic> ||
        stock is! Map<String, dynamic> ||
        taxes is! List ||
        permissions is! Map<String, dynamic> ||
        permissions.values.any((value) => value is! bool)) {
      throw invalidResponse;
    }
    final uom = stock['uom'];
    if (stock['tracked'] is! bool || uom is! Map<String, dynamic>) {
      throw invalidResponse;
    }
    final uomName = uom['name'];
    final rounding = uom['rounding'];
    final locationId = stock['location_id'];
    if (uomName is! String ||
        (rounding != null && rounding is! String) ||
        (locationId != null && (locationId is! int || locationId <= 0))) {
      throw invalidResponse;
    }
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'price': _decimal(price['amount']),
      'stock_quantity': stock['quantity'] == null
          ? null
          : _decimal(stock['quantity']),
      'uom': uomName,
      'default_code': defaultCode,
      'taxes': [for (final tax in taxes) _tax(tax)],
      'currency': _currency(price['currency']),
      'category': _category(data['category']),
      'description': description,
      'version': version,
      'stock_tracked': stock['tracked'],
      'stock_adjustable': stock['adjustable'] == true,
      'stock_location_id': locationId,
      'uom_rounding': rounding,
      'permissions': Map<String, bool>.from(permissions),
    };
  }

  /// `ProductSummary` from `GET /products`.
  static Map<String, dynamic> summaryRecord(Object? data) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final id = data['id'];
    final name = data['name'];
    final barcode = data['barcode'];
    final price = data['list_price'];
    if (id is! int ||
        id <= 0 ||
        name is! String ||
        name.trim().isEmpty ||
        (barcode != null && barcode is! String) ||
        price is! Map<String, dynamic>) {
      throw invalidResponse;
    }
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'price': _decimal(price['amount']),
      'currency': _currency(price['currency']),
      'stock_quantity': data['stock_quantity'] == null
          ? null
          : _decimal(data['stock_quantity']),
    };
  }

  static Map<String, dynamic> _tax(Object? value) {
    if (value is! Map<String, dynamic>) throw invalidResponse;
    final id = value['id'];
    final name = value['name'];
    final type = value['amount_type'];
    if (id is! int || id <= 0 || name is! String || type is! String) {
      throw invalidResponse;
    }
    return {
      'id': id,
      'name': name,
      'amount': _number(value['amount']),
      'amount_type': type,
    };
  }

  static Map<String, dynamic>? _category(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) throw invalidResponse;
    final id = value['id'];
    final name = value['name'];
    if (id is! int || id <= 0 || name is! String) throw invalidResponse;
    return {'id': id, 'name': name};
  }

  static String _currency(Object? value) {
    if (value is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      throw invalidResponse;
    }
    return value;
  }

  /// Integral values stay integers so tax labels read `15%`, not `15.0%`.
  static num _number(Object? value) {
    final number = _decimal(value);
    return number == number.truncateToDouble() ? number.toInt() : number;
  }

  /// Contract decimals are strings such as `"125.00"` (optionally signed for
  /// stock that went negative).
  static double _decimal(Object? value) {
    if (value is! String ||
        !RegExp(r'^-?\d{1,12}(\.\d{1,6})?$').hasMatch(value)) {
      throw invalidResponse;
    }
    return double.parse(value);
  }
}
