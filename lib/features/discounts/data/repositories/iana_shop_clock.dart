import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/repositories/shop_clock.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// [ShopClock] over the IANA timezone database (`timezone` package, the
/// ten-year data set: only boundaries near today schedule a refresh).
class IanaShopClock implements ShopClock {
  new() {
    if (!_loaded) {
      tz_data.initializeTimeZones();
      _loaded = true;
    }
  }

  static var _loaded = false;

  tz.Location? _location(String timezone) {
    try {
      return tz.getLocation(timezone);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  @override
  DateTime? instant(String timezone, LocalDate date, TimeOfDayValue time) {
    final location = _location(timezone);
    if (location == null) return null;
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
  }

  @override
  LocalDate? dateAt(String timezone, DateTime utc) {
    final location = _location(timezone);
    if (location == null) return null;
    final local = tz.TZDateTime.from(utc, location);
    return LocalDate(local.year, local.month, local.day);
  }
}
