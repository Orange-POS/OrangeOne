import 'package:orange_one/core/formatting/money.dart';
import 'package:orange_one/features/products/domain/use_cases/update_product_price.dart';
import 'package:orange_one/l10n/l10n.dart';

/// The text of the price confirmation (shown in the shared confirm dialog):
/// product, current price and the new price.
String priceConfirmText(
  AppLocalizations l10n,
  PriceChangeConfirmation confirmation,
) => l10n.priceConfirmMessage(
  confirmation.product.name,
  formatAmount(confirmation.product.price),
  confirmation.price.formatted,
);
