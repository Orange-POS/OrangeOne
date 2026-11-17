import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';

import '../../../support/discount_fakes.dart';

void main() {
  // Today 12:00 local; the example of the issue: a fixed price from
  // yesterday through tomorrow and a percentage through the month's end.
  final now = DateTime(2030, 1, 15, 12);
  LocalDate day(DateTime value) =>
      LocalDate(value.year, value.month, value.day);
  DiscountSchedule period(DateTime start, DateTime? end) => DiscountSchedule(
    startDate: day(start),
    startTime: const TimeOfDayValue(9, 0),
    endDate: end == null ? null : day(end),
    endTime: end == null ? null : const TimeOfDayValue(18, 0),
  );
  final yesterday = now.subtract(const Duration(days: 1));
  final tomorrow = now.add(const Duration(days: 1));
  final monthEnd = DateTime(2030, 1, 31);

  ProductDiscounts listOf(List<Discount> discounts) => ProductDiscounts(
    productId: 10,
    regularPrice: const DiscountMoney(10000, 'CHF'),
    counts: DiscountCounts(
      total: discounts.length,
      active: 0,
      scheduled: 0,
      expired: 0,
      paused: 0,
    ),
    limit: 20,
    discounts: discounts,
  );

  Discount fixed({DiscountStatus status = DiscountStatus.active}) => discountOf(
    type: DiscountType.fixedPrice,
    status: status,
    schedule: period(yesterday, tomorrow),
  );
  Discount percentage() =>
      discountOf(id: 2, schedule: period(yesterday, monthEnd));

  test('both overlapping discounts are flagged while both apply', () {
    final list = listOf([fixed(), percentage()]);
    expect(list.overlapping, {1, 2});
    // The next change is the fixed price ending tomorrow at 18:00.
    expect(list.nextChange(now), DateTime(2030, 1, 16, 18));
  });

  test('once the fixed price ended, the percentage runs without warning', () {
    final list = listOf([fixed(status: DiscountStatus.expired), percentage()]);
    expect(list.overlapping, isEmpty);
  });

  test('paused, archived and single discounts never count as overlap', () {
    expect(listOf([percentage()]).overlapping, isEmpty);
    expect(
      listOf([percentage(), discountOf(id: 3, paused: true)]).overlapping,
      isEmpty,
    );
    expect(
      listOf([
        percentage(),
        discountOf(id: 4, active: false, status: DiscountStatus.archived),
      ]).overlapping,
      isEmpty,
    );
  });

  test('three discounts in effect flag all three', () {
    final list = listOf([fixed(), percentage(), discountOf(id: 3)]);
    expect(list.overlapping, {1, 2, 3});
  });

  test('no re-read is needed while fewer than two could overlap', () {
    expect(listOf([percentage()]).nextChange(now), isNull);
    expect(
      listOf([percentage(), discountOf(id: 3, paused: true)]).nextChange(now),
      isNull,
    );
  });

  test('a scheduled start and a repeat day are changes too', () {
    final later = discountOf(
      id: 3,
      status: DiscountStatus.scheduled,
      schedule: period(tomorrow, null),
    );
    // Starts tomorrow 09:00, before the fixed price ends at 18:00.
    expect(listOf([fixed(), later]).nextChange(now), DateTime(2030, 1, 16, 9));
    const weekly = Discount(
      id: 5,
      productId: 10,
      type: DiscountType.percentage,
      label: '10% off',
      percent: '10',
      regularPrice: DiscountMoney(10000, 'CHF'),
      preview: DiscountPreview(
        savings: DiscountMoney(1000, 'CHF'),
        savingsPercent: '10.00',
      ),
      repeat: DiscountRepeat(RepeatType.weekly, weekdays: {Weekday.sun}),
      status: DiscountStatus.active,
      appliesNow: true,
      paused: false,
      active: true,
      version: 'v1',
    );
    // A repeat schedule can switch at midnight.
    expect(
      listOf([percentage(), weekly]).nextChange(now),
      DateTime(2030, 1, 16),
    );
  });
}
