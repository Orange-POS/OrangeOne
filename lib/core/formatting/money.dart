/// A money amount with two decimals, as the app shows prices (`25.00`).
String formatAmount(double amount) => amount.toStringAsFixed(2);

/// An amount with its currency code in front (`USD 25.00`); the amount
/// alone when [currency] is unknown, rather than a guessed currency.
String formatMoney(double amount, {String? currency}) {
  final code = currency?.trim() ?? '';
  final value = formatAmount(amount);
  return code.isEmpty ? value : '$code $value';
}
