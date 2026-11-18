import 'package:orange_one/features/discounts/domain/entities/discount.dart';

/// Contract field paths (`error.details[].field`), shared by the client
/// checks and the server's field errors so both land on the same input.
abstract final class DiscountField {
  static const type = 'type';
  static const fixedPrice = 'fixed_price';
  static const percent = 'percent';
  static const bundleQuantity = 'bundle_quantity';
  static const bundlePrice = 'bundle_price';
  static const schedule = 'schedule';
  static const startDate = 'schedule.start_date';
  static const startTime = 'schedule.start_time';
  static const endDate = 'schedule.end_date';
  static const endTime = 'schedule.end_time';
  static const repeat = 'repeat';
  static const weekdays = 'repeat.weekdays';
  static const annualDate = 'repeat.annual_date';
  static const minimumQuantity = 'minimum_quantity';

  /// The input a server field path belongs to (`schedule.end_date` and
  /// `schedule.end_time` share the end row, and so on).
  static String inputOf(String field) => switch (field) {
    endTime => endDate,
    startTime => startDate,
    _ when field.startsWith('repeat.weekdays') => weekdays,
    _ when field.startsWith('repeat.annual_date') => annualDate,
    _ => field,
  };
}

/// Why a field cannot be sent. Server detail codes map onto these where
/// they mean the same; unknown server codes show the server's message.
enum DiscountIssue {
  required,
  invalidAmount,
  notBelowRegularPrice,
  invalidPercent,
  invalidBundleQuantity,
  endBeforeStart,
  endInPast,
  invalidTime,
  weekdaysRequired,
  invalidAnnualDate,
  invalidQuantity,
  invalidQuantityStep;

  /// The client issue for a server detail code, or null when unknown.
  static DiscountIssue? fromServerCode(String code) => switch (code) {
    'REQUIRED' => required,
    'INVALID_DECIMAL' || 'INVALID_PRECISION' => invalidAmount,
    'NOT_BELOW_REGULAR_PRICE' => notBelowRegularPrice,
    'INVALID_PERCENT' => invalidPercent,
    'INVALID_BUNDLE_QUANTITY' => invalidBundleQuantity,
    'END_BEFORE_START' => endBeforeStart,
    'END_IN_PAST' => endInPast,
    'INVALID_TIME' || 'INVALID_DATE' => invalidTime,
    'INVALID_ANNUAL_DATE' => invalidAnnualDate,
    'INVALID_QUANTITY' => invalidQuantity,
    'INVALID_QUANTITY_STEP' => invalidQuantityStep,
    _ => null,
  };
}

/// The live preview while typing. Never authoritative: the server's
/// `preview` decides after saving.
class DraftPreview {
  const new({
    required this.savingsCents,
    this.unitPriceCents,
    this.bundleQuantity,
    this.bundlePriceCents,
    this.bundleRegularCents,
    this.percent,
  });

  final int? unitPriceCents;
  final int? bundleQuantity;
  final int? bundlePriceCents;
  final int? bundleRegularCents;

  /// The entered percentage as typed (percentage type only).
  final String? percent;
  final int savingsCents;
}

/// The full state of the shared Create/Edit Discount form: the
/// `DiscountInput` of `POST /products/{id}/discounts` and
/// `PUT /discounts/{id}`. Text fields are kept as typed.
class DiscountDraft {
  const new({
    this.type,
    this.fixedPrice = '',
    this.percent = '',
    this.bundleQuantity = '',
    this.bundlePrice = '',
    this.schedule,
    this.repeat = DiscountRepeat.none,
    this.minimumQuantity = '',
  });

  /// The form filled with a stored discount (edit mode).
  factory fromDiscount(Discount discount) => DiscountDraft(
    type: discount.type,
    fixedPrice: discount.fixedPrice?.amount ?? '',
    percent: discount.percent ?? '',
    bundleQuantity: discount.bundleQuantity?.toString() ?? '',
    bundlePrice: discount.bundlePrice?.amount ?? '',
    schedule: discount.schedule,
    repeat: discount.repeat,
    minimumQuantity: discount.minimumQuantity ?? '',
  );

  /// Null until a Discount Type tab is chosen.
  final DiscountType? type;
  final String fixedPrice;
  final String percent;
  final String bundleQuantity;
  final String bundlePrice;

  /// Null = "Not set".
  final DiscountSchedule? schedule;
  final DiscountRepeat repeat;

  /// Empty = No Minimum.
  final String minimumQuantity;

  DiscountDraft copyWith({
    DiscountType? type,
    String? fixedPrice,
    String? percent,
    String? bundleQuantity,
    String? bundlePrice,
    DiscountRepeat? repeat,
    String? minimumQuantity,
  }) => DiscountDraft(
    type: type ?? this.type,
    fixedPrice: fixedPrice ?? this.fixedPrice,
    percent: percent ?? this.percent,
    bundleQuantity: bundleQuantity ?? this.bundleQuantity,
    bundlePrice: bundlePrice ?? this.bundlePrice,
    schedule: schedule,
    repeat: repeat ?? this.repeat,
    minimumQuantity: minimumQuantity ?? this.minimumQuantity,
  );

  /// The same draft with another schedule (null clears it: "Not set").
  DiscountDraft withSchedule(DiscountSchedule? value) => DiscountDraft(
    type: type,
    fixedPrice: fixedPrice,
    percent: percent,
    bundleQuantity: bundleQuantity,
    bundlePrice: bundlePrice,
    schedule: value,
    repeat: repeat,
    minimumQuantity: minimumQuantity,
  );

  static int? _percentHundredths(String raw) {
    final match = RegExp(r'^(\d{1,3})(?:[.,](\d{1,2}))?$')
        .firstMatch(raw.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) * 100 +
        int.parse((match.group(2) ?? '').padRight(2, '0'));
  }

  static int? _bundleQuantity(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^[1-9]\d{0,5}$').hasMatch(value)) return null;
    return int.parse(value);
  }

  /// Client checks against [regularCents] (the product's current list
  /// price). Empty when the draft can be sent; the server still validates
  /// every rule (price precision, quantity steps, timezone gaps, limits).
  Map<String, DiscountIssue> validate(int regularCents) {
    final issues = <String, DiscountIssue>{};
    switch (type) {
      case null:
        issues[DiscountField.type] = DiscountIssue.required;
      case DiscountType.fixedPrice:
        final price = fixedPrice.trim();
        final cents = DiscountMoney.parseCents(price);
        if (price.isEmpty) {
          issues[DiscountField.fixedPrice] = DiscountIssue.required;
        } else if (cents == null) {
          issues[DiscountField.fixedPrice] = DiscountIssue.invalidAmount;
        } else if (cents >= regularCents) {
          issues[DiscountField.fixedPrice] = DiscountIssue.notBelowRegularPrice;
        }
      case DiscountType.percentage:
        final value = percent.trim();
        final hundredths = _percentHundredths(value);
        if (value.isEmpty) {
          issues[DiscountField.percent] = DiscountIssue.required;
        } else if (hundredths == null ||
            hundredths <= 0 ||
            hundredths > 10000) {
          issues[DiscountField.percent] = DiscountIssue.invalidPercent;
        }
      case DiscountType.collective:
        final quantityText = bundleQuantity.trim();
        final quantity = _bundleQuantity(quantityText);
        if (quantityText.isEmpty) {
          issues[DiscountField.bundleQuantity] = DiscountIssue.required;
        } else if (quantity == null || quantity < 2) {
          issues[DiscountField.bundleQuantity] =
              DiscountIssue.invalidBundleQuantity;
        }
        final priceText = bundlePrice.trim();
        final cents = DiscountMoney.parseCents(priceText);
        if (priceText.isEmpty) {
          issues[DiscountField.bundlePrice] = DiscountIssue.required;
        } else if (cents == null) {
          issues[DiscountField.bundlePrice] = DiscountIssue.invalidAmount;
        } else if (quantity != null &&
            quantity >= 2 &&
            cents >= quantity * regularCents) {
          issues[DiscountField.bundlePrice] =
              DiscountIssue.notBelowRegularPrice;
        }
    }
    final period = schedule;
    if (period != null) {
      if ((period.endDate == null) != (period.endTime == null)) {
        issues[DiscountField.endDate] = DiscountIssue.required;
      } else if (period.hasEnd) {
        final order = period.endDate!.compareTo(period.startDate);
        if (order < 0 ||
            (order == 0 && period.endTime!.compareTo(period.startTime) <= 0)) {
          issues[DiscountField.endDate] = DiscountIssue.endBeforeStart;
        }
      }
    }
    if (repeat.type == RepeatType.weekly && repeat.weekdays.isEmpty) {
      issues[DiscountField.weekdays] = DiscountIssue.weekdaysRequired;
    }
    if (repeat.type == RepeatType.yearly &&
        !(repeat.annualDate?.valid ?? false)) {
      issues[DiscountField.annualDate] = DiscountIssue.invalidAnnualDate;
    }
    final minimum = minimumQuantity.trim();
    if (minimum.isNotEmpty) {
      final match = RegExp(r'^\d{1,12}(?:[.,]\d{1,6})?$').hasMatch(minimum);
      if (!match || double.parse(minimum.replaceAll(',', '.')) <= 0) {
        issues[DiscountField.minimumQuantity] = DiscountIssue.invalidQuantity;
      }
    }
    return issues;
  }

  /// The live preview, or null until the value of the chosen type is valid.
  DraftPreview? preview(int regularCents) {
    final issues = validate(regularCents);
    switch (type) {
      case null:
        return null;
      case DiscountType.fixedPrice:
        if (issues.containsKey(DiscountField.fixedPrice)) return null;
        final cents = DiscountMoney.parseCents(fixedPrice)!;
        return DraftPreview(
          unitPriceCents: cents,
          savingsCents: regularCents - cents,
        );
      case DiscountType.percentage:
        if (issues.containsKey(DiscountField.percent)) return null;
        final hundredths = _percentHundredths(percent)!;
        // Half-up to the cent, like a price shown to the customer.
        final savings = (regularCents * hundredths + 5000) ~/ 10000;
        return DraftPreview(
          unitPriceCents: regularCents - savings,
          savingsCents: savings,
          percent: percent.trim().replaceAll(',', '.'),
        );
      case DiscountType.collective:
        if (issues.containsKey(DiscountField.bundleQuantity) ||
            issues.containsKey(DiscountField.bundlePrice)) {
          return null;
        }
        final quantity = _bundleQuantity(bundleQuantity)!;
        final cents = DiscountMoney.parseCents(bundlePrice)!;
        return DraftPreview(
          bundleQuantity: quantity,
          bundlePriceCents: cents,
          bundleRegularCents: quantity * regularCents,
          savingsCents: quantity * regularCents - cents,
        );
    }
  }
}
