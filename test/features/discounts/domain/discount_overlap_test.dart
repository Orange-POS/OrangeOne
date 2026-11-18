import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/discounts/data/repositories/iana_shop_clock.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';

import '../../../support/discount_fakes.dart';

/// Schedules are shop-local times. Every expectation below is a UTC instant:
/// the result never depends on the phone's timezone (the old calculation
/// read schedule times in the phone's local time).
void main() {
  final clock = IanaShopClock();
  const fallback = Duration(minutes: 15);

  DiscountSchedule period(
    String zone,
    LocalDate start,
    TimeOfDayValue startTime, {
    LocalDate? end,
    TimeOfDayValue? endTime,
  }) => DiscountSchedule(
    startDate: start,
    startTime: startTime,
    endDate: end,
    endTime: endTime,
    timezone: zone,
  );

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

  DateTime? next(List<Discount> discounts, DateTime nowUtc) =>
      listOf(discounts).nextChange(nowUtc, clock, fallback: fallback);

  const zurich = 'Europe/Zurich';
  const nine = TimeOfDayValue(9, 0);
  const noon = TimeOfDayValue(12, 0);
  const six = TimeOfDayValue(18, 0);

  group(
    'the example of the issue (fixed through tomorrow, % to month end)',
    () {
      // Today is 2030-01-15 in Zurich (UTC+1 in winter).
      final fixed = discountOf(
        type: DiscountType.fixedPrice,
        schedule: period(
          zurich,
          const LocalDate(2030, 1, 14),
          nine,
          end: const LocalDate(2030, 1, 16),
          endTime: six,
        ),
      );
      final percentage = discountOf(
        id: 2,
        schedule: period(
          zurich,
          const LocalDate(2030, 1, 14),
          nine,
          end: const LocalDate(2030, 1, 31),
          endTime: six,
        ),
      );

      test('both are flagged while the server says both apply', () {
        expect(listOf([fixed, percentage]).overlapping, {1, 2});
      });

      test('the next read is when the fixed price ends, in shop time', () {
        // 2030-01-16 18:00 Zurich = 17:00 UTC.
        expect(
          next([fixed, percentage], DateTime.utc(2030, 1, 15, 11)),
          DateTime.utc(2030, 1, 16, 17),
        );
      });

      test('once it ended, the percentage runs without warning', () {
        final ended = discountOf(
          type: DiscountType.fixedPrice,
          status: DiscountStatus.expired,
          appliesNow: false,
          schedule: fixed.schedule,
        );
        expect(listOf([ended, percentage]).overlapping, isEmpty);
      });
    },
  );

  test('a start at 12:00 Zurich in January is read at 11:00 UTC, not 12:00 '
      '(the review case: shop in Zurich, phone in UTC)', () {
    final running = discountOf(
      schedule: period(zurich, const LocalDate(2030, 1, 1), nine),
    );
    final starting = discountOf(
      id: 2,
      status: DiscountStatus.scheduled,
      appliesNow: false,
      schedule: period(zurich, const LocalDate(2030, 1, 15), noon),
    );
    expect(
      next([running, starting], DateTime.utc(2030, 1, 15, 10)),
      DateTime.utc(2030, 1, 15, 11),
    );
  });

  test('daylight saving time follows the shop zone (12:00 Zurich in July '
      'is 10:00 UTC)', () {
    final running = discountOf(
      schedule: period(zurich, const LocalDate(2030, 7, 1), nine),
    );
    final starting = discountOf(
      id: 2,
      status: DiscountStatus.scheduled,
      appliesNow: false,
      schedule: period(zurich, const LocalDate(2030, 7, 15), noon),
    );
    expect(
      next([running, starting], DateTime.utc(2030, 7, 15, 9)),
      DateTime.utc(2030, 7, 15, 10),
    );
  });

  test('a scheduled start without an end date is still ahead when the '
      'phone is ahead of the shop', () {
    // Shop in New York (UTC-5). At 12:00 UTC it is 07:00 there, while a
    // phone in Tokyo already shows 21:00: the old calculation took the
    // 09:00 start as past and scheduled no read at all.
    const newYork = 'America/New_York';
    final running = discountOf(
      schedule: period(newYork, const LocalDate(2030, 1, 1), nine),
    );
    final starting = discountOf(
      id: 2,
      status: DiscountStatus.scheduled,
      appliesNow: false,
      schedule: period(newYork, const LocalDate(2030, 1, 15), nine),
    );
    expect(
      next([running, starting], DateTime.utc(2030, 1, 15, 12)),
      DateTime.utc(2030, 1, 15, 14),
    );
  });

  test("a repeat schedule switches at the shop's midnight", () {
    // Auckland is UTC+13 in January: midnight of 16 January there is
    // 11:00 UTC on 15 January.
    const auckland = 'Pacific/Auckland';
    final running = discountOf(
      schedule: period(auckland, const LocalDate(2030, 1, 1), nine),
    );
    final weekly = discountOf(
      id: 2,
      repeat: const DiscountRepeat(RepeatType.weekly, weekdays: {Weekday.thu}),
      schedule: period(auckland, const LocalDate(2030, 1, 1), nine),
    );
    expect(
      next([running, weekly], DateTime.utc(2030, 1, 15, 1)),
      DateTime.utc(2030, 1, 15, 11),
    );
  });

  test('an unknown or missing shop timezone falls back to a periodic '
      'read', () {
    final now = DateTime.utc(2030, 1, 15, 10);
    final unknown = discountOf(
      schedule: period('Mars/Olympus', const LocalDate(2030, 3, 1), nine),
    );
    final missing = discountOf(
      id: 2,
      schedule: const DiscountSchedule(
        startDate: LocalDate(2030, 3, 1),
        startTime: nine,
      ),
    );
    expect(next([unknown, missing], now), now.add(fallback));
  });

  test('no read is scheduled while fewer than two could overlap', () {
    final one = discountOf(
      schedule: period(zurich, const LocalDate(2030, 1, 20), nine),
    );
    final now = DateTime.utc(2030, 1, 15);
    expect(next([one], now), isNull);
    expect(next([one, discountOf(id: 3, paused: true)], now), isNull);
    expect(
      next([
        one,
        discountOf(id: 4, active: false, status: DiscountStatus.archived),
      ], now),
      isNull,
    );
  });

  test('three discounts in effect flag all three', () {
    expect(
      listOf([discountOf(), discountOf(id: 2), discountOf(id: 3)]).overlapping,
      {1, 2, 3},
    );
  });
}
