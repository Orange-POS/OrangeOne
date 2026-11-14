import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';

/// Maps the Mobile API 1.1 discount payloads (`Discount`,
/// `ProductDiscountList`). Anything that does not match the contract is a
/// protocol failure; optional members default safely.
abstract final class DiscountModel {
  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : throw invalidResponse;

  static int _id(Object? value) =>
      value is int && value > 0 ? value : throw invalidResponse;

  static int _count(Object? value) =>
      value is int && value >= 0 ? value : throw invalidResponse;

  static String _string(Object? value) =>
      value is String ? value : throw invalidResponse;

  static bool _bool(Object? value) =>
      value is bool ? value : throw invalidResponse;

  static DiscountMoney _money(Object? value) {
    final map = _map(value);
    final cents = DiscountMoney.parseCents(_string(map['amount']));
    final currency = _string(map['currency']);
    if (cents == null || currency.isEmpty) throw invalidResponse;
    return DiscountMoney(cents, currency);
  }

  static DiscountMoney? _optionalMoney(Object? value) =>
      value == null ? null : _money(value);

  static DiscountSchedule? _schedule(Object? value) {
    if (value == null) return null;
    final map = _map(value);
    final startDate = LocalDate.tryParse(map['start_date']);
    final startTime = TimeOfDayValue.tryParse(map['start_time']);
    final endDate = map['end_date'] == null
        ? null
        : LocalDate.tryParse(map['end_date']) ?? (throw invalidResponse);
    final endTime = map['end_time'] == null
        ? null
        : TimeOfDayValue.tryParse(map['end_time']) ?? (throw invalidResponse);
    if (startDate == null || startTime == null) throw invalidResponse;
    final timezone = map['timezone'];
    return DiscountSchedule(
      startDate: startDate,
      startTime: startTime,
      endDate: endDate,
      endTime: endTime,
      timezone: timezone is String ? timezone : null,
    );
  }

  static DiscountRepeat _repeat(Object? value) {
    final map = _map(value);
    final type = RepeatType.fromWire(map['type']) ?? (throw invalidResponse);
    final days = map['weekdays'];
    if (days != null && days is! List) throw invalidResponse;
    final weekdays = {
      for (final day in (days as List?) ?? const [])
        Weekday.fromWire(day) ?? (throw invalidResponse),
    };
    final annual = map['annual_date'];
    AnnualDate? annualDate;
    if (annual != null) {
      final date = _map(annual);
      final month = date['month'];
      final day = date['day'];
      if (month is! int || day is! int) throw invalidResponse;
      annualDate = AnnualDate(month, day);
    }
    return DiscountRepeat(type, weekdays: weekdays, annualDate: annualDate);
  }

  static Discount parse(Object? value) {
    final map = _map(value);
    final type = DiscountType.fromWire(map['type']) ?? (throw invalidResponse);
    final preview = _map(map['preview']);
    final warnings = map['warnings'];
    if (warnings is! List) throw invalidResponse;
    final quantity = map['bundle_quantity'];
    final minimum = map['minimum_quantity'];
    final percent = map['percent'];
    if (quantity != null && quantity is! String) throw invalidResponse;
    if (minimum != null && minimum is! String) throw invalidResponse;
    if (percent != null && percent is! String) throw invalidResponse;
    final bundleQuantity = quantity == null
        ? null
        : int.tryParse(quantity as String) ?? (throw invalidResponse);
    final version = _string(map['version']);
    if (version.isEmpty) throw invalidResponse;
    return Discount(
      id: _id(map['id']),
      productId: _id(map['product_id']),
      type: type,
      label: _string(map['label']),
      fixedPrice: _optionalMoney(map['fixed_price']),
      percent: percent as String?,
      bundleQuantity: bundleQuantity,
      bundlePrice: _optionalMoney(map['bundle_price']),
      regularPrice: _money(map['regular_price']),
      preview: DiscountPreview(
        unitPrice: _optionalMoney(preview['unit_price']),
        bundleRegularPrice: _optionalMoney(preview['bundle_regular_price']),
        savings: _money(preview['savings']),
        savingsPercent: _string(preview['savings_percent']),
      ),
      schedule: _schedule(map['schedule']),
      repeat: _repeat(map['repeat']),
      minimumQuantity: minimum as String?,
      status: DiscountStatus.fromWire(map['status']),
      appliesNow: _bool(map['applies_now']),
      paused: _bool(map['paused']),
      warnings: [
        for (final warning in warnings)
          DiscountWarning(
            _string(_map(warning)['code']),
            _string(_map(warning)['message']),
          ),
      ],
      active: _bool(map['active']),
      version: version,
    );
  }

  static ProductDiscounts parseList(Object? value) {
    final map = _map(value);
    final counts = _map(map['counts']);
    final discounts = map['discounts'];
    if (discounts is! List) throw invalidResponse;
    return ProductDiscounts(
      productId: _id(map['product_id']),
      regularPrice: _money(map['regular_price']),
      counts: DiscountCounts(
        total: _count(counts['total']),
        active: _count(counts['active']),
        scheduled: _count(counts['scheduled']),
        expired: _count(counts['expired']),
        paused: _count(counts['paused']),
      ),
      limit: _count(map['limit']),
      discounts: [for (final discount in discounts) parse(discount)],
    );
  }
}

/// The `DiscountInput` body: the whole form state, unused members null.
abstract final class DiscountInputModel {
  static String _decimal(String value) => value.trim().replaceAll(',', '.');

  static String? _amount(DiscountType? type, DiscountType wanted, String raw) {
    if (type != wanted) return null;
    final cents = DiscountMoney.parseCents(raw);
    return cents == null ? _decimal(raw) : DiscountMoney(cents, '').amount;
  }

  static Map<String, dynamic> toJson(DiscountDraft draft) {
    final type = draft.type;
    if (type == null) throw ArgumentError.value(draft, 'draft', 'no type');
    final schedule = draft.schedule;
    final repeat = draft.repeat;
    return {
      'type': type.wire,
      'fixed_price': _amount(type, DiscountType.fixedPrice, draft.fixedPrice),
      'percent': type == DiscountType.percentage
          ? _decimal(draft.percent)
          : null,
      'bundle_quantity': type == DiscountType.collective
          ? draft.bundleQuantity.trim()
          : null,
      'bundle_price': _amount(type, DiscountType.collective, draft.bundlePrice),
      'schedule': schedule == null
          ? null
          : {
              'start_date': schedule.startDate.iso,
              'start_time': schedule.startTime.formatted,
              'end_date': schedule.hasEnd ? schedule.endDate!.iso : null,
              'end_time': schedule.hasEnd ? schedule.endTime!.formatted : null,
            },
      'repeat': {
        'type': repeat.type.name,
        'weekdays': repeat.type == RepeatType.weekly
            ? [
                for (final day in Weekday.values)
                  if (repeat.weekdays.contains(day)) day.name,
              ]
            : null,
        'annual_date':
            repeat.type == RepeatType.yearly && repeat.annualDate != null
            ? {'month': repeat.annualDate!.month, 'day': repeat.annualDate!.day}
            : null,
      },
      'minimum_quantity': draft.minimumQuantity.trim().isEmpty
          ? null
          : _decimal(draft.minimumQuantity),
    };
  }
}
