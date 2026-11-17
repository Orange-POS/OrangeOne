import 'package:flutter/material.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

/// Query parameters of the discount routes.
Map<String, String> discountRouteQuery(
  DiscountScope scope, {
  int? discountId,
}) => {
  'barcode': scope.barcode,
  'product_id': '${scope.productId}',
  'discount_id': ?discountId?.toString(),
};

/// Shows a confirmed outcome (a form or action result) as a snack bar, with
/// the success haptic.
void showDiscountResult(BuildContext context, String? message) {
  if (message == null || !context.mounted) return;
  playHaptic(context, HapticEffect.success);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
