import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/data/models/product_access_model.dart';

import '../../../../support/product_api_fakes.dart';

void main() {
  test('permissions map every v2 capability; absent keys are denied', () {
    final all = ProductAccessModel.parse(productPermissions());
    expect([
      all.editName,
      all.updatePrice,
      all.readReferences,
      all.updateTaxes,
      all.updateCategory,
      all.createProduct,
      all.adjustStock,
      all.readHistory,
    ], everyElement(isTrue));
    final readOnly = ProductAccessModel.parse({'product_read': true});
    expect(readOnly.editName || readOnly.updatePrice, isFalse);
    expect(readOnly.adjustStock || readOnly.createProduct, isFalse);
  });

  test('non-boolean permissions are protocol errors', () {
    expect(
      () => ProductAccessModel.parse({'stock_adjust': 1}),
      throwsA(same(invalidResponse)),
    );
    expect(
      () => ProductAccessModel.parse(null),
      throwsA(same(invalidResponse)),
    );
  });
}
