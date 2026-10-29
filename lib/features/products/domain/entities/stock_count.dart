import 'package:orange_one/features/products/domain/entities/product_details.dart';

/// How a quantity changes the stock at the POS stock location.
enum StockOperation {
  /// Replaces the stock with the counted quantity.
  update,

  /// Increases the stock by the entered quantity.
  add,

  /// Decreases the stock by the entered quantity.
  remove;

  /// The stock after applying [amount] to [current]. Only a preview: the
  /// backend computes the authoritative result under its own lock.
  double resultFor(double current, double amount) {
    final raw = switch (this) {
      StockOperation.update => amount,
      StockOperation.add => current + amount,
      StockOperation.remove => current - amount,
    };
    // Drops binary floating point noise (150.1 + 40.2).
    return double.parse(raw.toStringAsFixed(6));
  }

  /// `operation` value of `POST /products/{id}/stock-movements`; Update is a
  /// count and uses `stock-adjustments` instead.
  String? get movementName => switch (this) {
    StockOperation.update => null,
    StockOperation.add => 'add',
    StockOperation.remove => 'remove',
  };
}

/// Why a stock quantity cannot be submitted (localized by the screen).
enum StockInputIssue {
  /// Not a non-negative decimal number.
  invalid,

  /// A fraction on a unit that is counted in whole numbers.
  wholeNumber,

  /// More decimals than the unit allows.
  decimals,

  /// Add and Remove need a quantity greater than zero.
  zero,

  /// Remove would take the stock below zero.
  exceedsStock,

  /// The stock cannot be changed from the app.
  unavailable,
}

/// A rejected stock quantity. It is a [FormatException] so existing handlers
/// keep working; the screen shows [issue] in the selected language.
class StockInputException extends FormatException {
  const new(this.issue, super.message, {this.decimals});
  final StockInputIssue issue;

  /// Allowed decimals for [StockInputIssue.decimals].
  final int? decimals;
}

/// A quantity entered for one stock operation of one product.
class StockCount {
  const new _(this.text, this.quantity);

  /// Accepts a non-negative quantity with at most [maxDecimals] decimals
  /// (the unit rounding; 6 when unknown).
  factory parse(String raw, {int? maxDecimals}) {
    final value = raw.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d{1,12})(?:\.(\d{1,6}))?$').firstMatch(value);
    if (match == null) {
      throw const StockInputException(
        StockInputIssue.invalid,
        'Enter the counted quantity as a non-negative number.',
      );
    }
    final fraction = match.group(2) ?? '';
    final decimals = maxDecimals ?? 6;
    if (fraction.replaceFirst(RegExp(r'0+$'), '').length > decimals) {
      throw StockInputException(
        decimals == 0 ? StockInputIssue.wholeNumber : StockInputIssue.decimals,
        decimals == 0
            ? 'Enter a whole number for this unit.'
            : 'Use at most $decimals decimal places for this unit.',
        decimals: decimals,
      );
    }
    final whole = match.group(1)!.replaceFirst(RegExp('^0+(?=.)'), '');
    final text = fraction.isEmpty ? whole : '$whole.$fraction';
    return StockCount._(text, double.parse(text));
  }

  /// Normalized decimal text sent to the backend (`12.5`, never `12,5`).
  final String text;
  final double quantity;
}

/// A confirmed stock change and the refreshed product.
class StockAdjustment {
  const new({
    required this.product,
    required this.previousQuantity,
    required this.newQuantity,
    this.operation = StockOperation.update,
  });
  final ProductDetails product;
  final double previousQuantity;
  final double newQuantity;
  final StockOperation operation;
  double get difference => newQuantity - previousQuantity;
}
