/// Product discounts of the OrangeONE Mobile API 1.1 (`product_discounts`).
/// Plain Dart: no Flutter, Riverpod or API payloads.
library;

enum DiscountType {
  fixedPrice('fixed_price'),
  percentage('percentage'),
  collective('collective');

  new(this.wire);

  /// The contract value (`DiscountType`).
  final String wire;

  static DiscountType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// Computed by the server at response time, never stored. A status this
/// app does not know is [unknown] and shown as not applying.
enum DiscountStatus {
  scheduled,
  active,
  expired,
  paused,
  archived,
  unknown;

  static DiscountStatus fromWire(Object? value) {
    for (final status in values) {
      if (status != unknown && status.name == value) return status;
    }
    return unknown;
  }
}

enum RepeatType {
  none,
  daily,
  weekly,
  weekends,
  yearly;

  static RepeatType? fromWire(Object? value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// ISO weekdays (Monday = 1), sent as `mon` … `sun`.
enum Weekday {
  mon,
  tue,
  wed,
  thu,
  fri,
  sat,
  sun;

  int get iso => index + 1;

  static Weekday? fromWire(Object? value) {
    for (final day in values) {
      if (day.name == value) return day;
    }
    return null;
  }
}

/// A wall-clock time `HH:MM` in the shop timezone.
class TimeOfDayValue implements Comparable<TimeOfDayValue> {
  const new(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'hour out of range'),
      assert(minute >= 0 && minute < 60, 'minute out of range');

  /// Parses `HH:MM`; null when malformed.
  static TimeOfDayValue? tryParse(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) return null;
    return TimeOfDayValue(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  final int hour;
  final int minute;

  String get formatted =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(TimeOfDayValue other) =>
      (hour * 60 + minute) - (other.hour * 60 + other.minute);
}

/// A calendar date in the shop timezone (no time, no UTC conversion).
class LocalDate implements Comparable<LocalDate> {
  const new(this.year, this.month, this.day);

  /// Parses `YYYY-MM-DD` of a real calendar day; null otherwise.
  static LocalDate? tryParse(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final date = LocalDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final check = DateTime.utc(date.year, date.month, date.day);
    return check.year == date.year &&
            check.month == date.month &&
            check.day == date.day
        ? date
        : null;
  }

  final int year;
  final int month;
  final int day;

  /// Weekday of this date (proleptic Gregorian, independent of timezones).
  Weekday get weekday =>
      Weekday.values[DateTime.utc(year, month, day).weekday - 1];

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) => year != other.year
      ? year - other.year
      : month != other.month
      ? month - other.month
      : day - other.day;
}

/// Validity period ("Date & Time"). No end = "No End Date".
class DiscountSchedule {
  const new({
    required this.startDate,
    required this.startTime,
    this.endDate,
    this.endTime,
    this.timezone,
  });

  final LocalDate startDate;
  final TimeOfDayValue startTime;
  final LocalDate? endDate;
  final TimeOfDayValue? endTime;

  /// IANA timezone of the dates and times (shop timezone); null in a draft.
  final String? timezone;

  bool get hasEnd => endDate != null && endTime != null;
}

/// Day of the year for yearly repeats (29 February is rejected).
class AnnualDate {
  const new(this.month, this.day);

  final int month;
  final int day;

  /// A real day of a non-leap year.
  bool get valid {
    if (month < 1 || month > 12 || day < 1) return false;
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return day <= days[month - 1];
  }
}

/// Repeat Schedule: the eligible days inside the validity period.
class DiscountRepeat {
  const new(this.type, {this.weekdays = const {}, this.annualDate});

  static const none = DiscountRepeat(RepeatType.none);

  final RepeatType type;

  /// The days of a weekly repeat (`[sat, sun]` for weekends in responses).
  final Set<Weekday> weekdays;
  final AnnualDate? annualDate;
}

/// A decimal amount of the contract (`Money`): the exact string the server
/// sent, kept in hundredths for arithmetic.
class DiscountMoney {
  const new(this.cents, this.currency);

  /// Parses a contract decimal string with at most two decimals; null when
  /// malformed or more precise than the currency.
  static int? parseCents(String value) {
    final match = RegExp(r'^(\d{1,12})(?:[.,](\d{1,2}))?$')
        .firstMatch(value.trim());
    if (match == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return int.parse(match.group(1)!) * 100 + int.parse(fraction);
  }

  final int cents;
  final String currency;

  String get amount =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  /// `CHF 80.00`.
  String get display => '$currency $amount';
}

/// Server-calculated prices at the current regular price.
class DiscountPreview {
  const new({
    required this.savings,
    required this.savingsPercent,
    this.unitPrice,
    this.bundleRegularPrice,
  });

  /// Final unit price (fixed price and percentage); null for collective.
  final DiscountMoney? unitPrice;

  /// Bundle quantity × regular price (collective); null otherwise.
  final DiscountMoney? bundleRegularPrice;
  final DiscountMoney savings;
  final String savingsPercent;
}

class DiscountWarning {
  const new(this.code, this.message);
  final String code;
  final String message;
}

class Discount {
  const new({
    required this.id,
    required this.productId,
    required this.type,
    required this.label,
    required this.regularPrice,
    required this.preview,
    required this.repeat,
    required this.status,
    required this.appliesNow,
    required this.paused,
    required this.active,
    required this.version,
    this.fixedPrice,
    this.percent,
    this.bundleQuantity,
    this.bundlePrice,
    this.schedule,
    this.minimumQuantity,
    this.warnings = const [],
  });

  final int id;
  final int productId;
  final DiscountType type;

  /// Localised title from the server ("20% off", "5 for CHF 400.00").
  final String label;
  final DiscountMoney? fixedPrice;

  /// Percentage string as sent (`20`, `12.5`).
  final String? percent;
  final int? bundleQuantity;
  final DiscountMoney? bundlePrice;
  final DiscountMoney regularPrice;
  final DiscountPreview preview;

  /// Null = "Not set": applies from creation until archived.
  final DiscountSchedule? schedule;
  final DiscountRepeat repeat;

  /// Decimal string; null = No Minimum.
  final String? minimumQuantity;
  final DiscountStatus status;
  final bool appliesNow;
  final bool paused;
  final List<DiscountWarning> warnings;

  /// False once archived.
  final bool active;

  /// Optimistic-concurrency token for `If-Match`.
  final String version;

  bool get archived => !active || status == DiscountStatus.archived;

  /// Archived discounts cannot be edited, paused or resumed.
  bool get editable => !archived;
  bool get canPause => !archived && !paused;
  bool get canResume => !archived && paused;
}

class DiscountCounts {
  const new({
    required this.total,
    required this.active,
    required this.scheduled,
    required this.expired,
    required this.paused,
  });

  /// "Total Discounts": not archived, paused included.
  final int total;
  final int active;
  final int scheduled;
  final int expired;
  final int paused;
}

/// `GET /products/{id}/discounts`.
class ProductDiscounts {
  const new({
    required this.productId,
    required this.regularPrice,
    required this.counts,
    required this.limit,
    required this.discounts,
  });

  final int productId;
  final DiscountMoney regularPrice;
  final DiscountCounts counts;

  /// Maximum discounts that are not archived per product.
  final int limit;
  final List<Discount> discounts;

  bool get limitReached => counts.total >= limit;
}
