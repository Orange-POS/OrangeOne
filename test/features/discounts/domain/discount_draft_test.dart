import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';

/// Client checks and the live preview at a regular price of CHF 100.00.
void main() {
  const regular = 10000;

  Map<String, DiscountIssue> issues(DiscountDraft draft) =>
      draft.validate(regular);

  test('a type must be chosen', () {
    expect(issues(const DiscountDraft()), {
      DiscountField.type: DiscountIssue.required,
    });
    expect(const DiscountDraft().preview(regular), isNull);
  });

  group('fixed price', () {
    const draft = DiscountDraft(type: DiscountType.fixedPrice);

    test('required, two decimals, below the regular price', () {
      expect(issues(draft)[DiscountField.fixedPrice], DiscountIssue.required);
      expect(
        issues(draft.copyWith(fixedPrice: '8.005'))[DiscountField.fixedPrice],
        DiscountIssue.invalidAmount,
      );
      expect(
        issues(draft.copyWith(fixedPrice: '100'))[DiscountField.fixedPrice],
        DiscountIssue.notBelowRegularPrice,
      );
      expect(issues(draft.copyWith(fixedPrice: '80,50')), isEmpty);
    });

    test('preview: CHF 80.00 saves CHF 20.00', () {
      final preview = draft.copyWith(fixedPrice: '80').preview(regular)!;
      expect(preview.unitPriceCents, 8000);
      expect(preview.savingsCents, 2000);
    });
  });

  group('percentage', () {
    const draft = DiscountDraft(type: DiscountType.percentage);

    test('above 0 and up to 100 with two decimals', () {
      for (final bad in ['0', '100.01', '12.345', 'x', '101']) {
        expect(
          issues(draft.copyWith(percent: bad))[DiscountField.percent],
          DiscountIssue.invalidPercent,
          reason: bad,
        );
      }
      for (final good in ['20', '0.5', '100', '12,5']) {
        expect(issues(draft.copyWith(percent: good)), isEmpty, reason: good);
      }
    });

    test('preview rounds half up to the cent', () {
      final preview = draft.copyWith(percent: '20').preview(regular)!;
      expect(preview.unitPriceCents, 8000);
      expect(preview.percent, '20');
      // 33.33% of 9.95 = 3.316… → 3.32 off, 6.63 remains.
      expect(
        draft.copyWith(percent: '33.33').preview(995)!.unitPriceCents,
        663,
      );
    });
  });

  group('collective', () {
    const draft = DiscountDraft(type: DiscountType.collective);

    test('whole bundle of at least 2, price below the regular bundle', () {
      final none = issues(draft);
      expect(none[DiscountField.bundleQuantity], DiscountIssue.required);
      expect(none[DiscountField.bundlePrice], DiscountIssue.required);
      expect(
        issues(
          draft.copyWith(bundleQuantity: '1', bundlePrice: '80'),
        )[DiscountField.bundleQuantity],
        DiscountIssue.invalidBundleQuantity,
      );
      expect(
        issues(
          draft.copyWith(bundleQuantity: '5', bundlePrice: '500'),
        )[DiscountField.bundlePrice],
        DiscountIssue.notBelowRegularPrice,
      );
      expect(
        issues(draft.copyWith(bundleQuantity: '5', bundlePrice: '400')),
        isEmpty,
      );
    });

    test('preview: 5 for CHF 400.00 of a CHF 500.00 bundle', () {
      final preview = draft
          .copyWith(bundleQuantity: '5', bundlePrice: '400')
          .preview(regular)!;
      expect(preview.bundleRegularCents, 50000);
      expect(preview.savingsCents, 10000);
    });
  });

  group('schedule and repeat', () {
    const base = DiscountDraft(type: DiscountType.percentage, percent: '20');
    const start = LocalDate(2026, 10, 14);
    const nine = TimeOfDayValue(9, 0);

    test('the end must follow the start; No End Date is valid', () {
      expect(
        issues(
          base.withSchedule(
            const DiscountSchedule(startDate: start, startTime: nine),
          ),
        ),
        isEmpty,
      );
      expect(
        issues(
          base.withSchedule(
            const DiscountSchedule(
              startDate: start,
              startTime: nine,
              endDate: start,
              endTime: nine,
            ),
          ),
        )[DiscountField.endDate],
        DiscountIssue.endBeforeStart,
      );
      expect(
        issues(
          base.withSchedule(
            const DiscountSchedule(
              startDate: start,
              startTime: nine,
              endDate: LocalDate(2026, 10, 21),
              endTime: nine,
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('weekly needs days; yearly needs a real day, not 29 February', () {
      expect(
        issues(base.copyWith(repeat: const DiscountRepeat(RepeatType.weekly))),
        {DiscountField.weekdays: DiscountIssue.weekdaysRequired},
      );
      expect(
        issues(
          base.copyWith(
            repeat: const DiscountRepeat(
              RepeatType.weekly,
              weekdays: {Weekday.sun},
            ),
          ),
        ),
        isEmpty,
      );
      for (final date in [
        null,
        const AnnualDate(2, 29),
        const AnnualDate(4, 31),
      ]) {
        expect(
          issues(
            base.copyWith(
              repeat: DiscountRepeat(RepeatType.yearly, annualDate: date),
            ),
          )[DiscountField.annualDate],
          DiscountIssue.invalidAnnualDate,
        );
      }
      expect(
        issues(
          base.copyWith(
            repeat: const DiscountRepeat(
              RepeatType.yearly,
              annualDate: AnnualDate(12, 25),
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('minimum quantity: empty or above zero', () {
      expect(issues(base.copyWith(minimumQuantity: '')), isEmpty);
      expect(issues(base.copyWith(minimumQuantity: '5')), isEmpty);
      for (final bad in ['0', '-1', 'x']) {
        expect(
          issues(
            base.copyWith(minimumQuantity: bad),
          )[DiscountField.minimumQuantity],
          DiscountIssue.invalidQuantity,
          reason: bad,
        );
      }
    });
  });

  test('server codes map onto client issues; fields onto inputs', () {
    expect(
      DiscountIssue.fromServerCode('NOT_BELOW_REGULAR_PRICE'),
      DiscountIssue.notBelowRegularPrice,
    );
    expect(DiscountIssue.fromServerCode('SOMETHING_NEW'), isNull);
    expect(DiscountField.inputOf('schedule.end_time'), DiscountField.endDate);
    expect(DiscountField.inputOf('repeat.weekdays[0]'), DiscountField.weekdays);
  });

  test('an unknown server status shows as not applying', () {
    expect(DiscountStatus.fromWire('frozen'), DiscountStatus.unknown);
    expect(DiscountStatus.fromWire('paused'), DiscountStatus.paused);
  });
}
