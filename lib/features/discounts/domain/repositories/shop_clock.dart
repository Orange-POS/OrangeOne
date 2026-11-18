import 'package:orange_one/features/discounts/domain/entities/discount.dart';

/// Converts between instants and the shop's wall clock. Discount schedules
/// are shop-local dates and times in an IANA timezone (`Europe/Zurich`); the
/// phone may be in any other timezone, so the phone's local time is never
/// used for them.
abstract interface class ShopClock {
  /// The UTC instant of [date] at [time] in [timezone], with that zone's
  /// daylight-saving rules; null when the timezone is unknown.
  DateTime? instant(String timezone, LocalDate date, TimeOfDayValue time);

  /// The shop's calendar date at the UTC instant [utc] in [timezone]; null
  /// when the timezone is unknown.
  LocalDate? dateAt(String timezone, DateTime utc);
}
