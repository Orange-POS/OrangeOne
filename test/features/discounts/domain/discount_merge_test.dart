import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_merge.dart';

void main() {
  const base = DiscountDraft(type: DiscountType.percentage, percent: '20');
  const schedule = DiscountSchedule(
    startDate: LocalDate(2026, 12, 1),
    startTime: TimeOfDayValue(9, 0),
  );

  test('changes to different parts both survive', () {
    final merge = DiscountMerge(
      base: base,
      mine: base.copyWith(percent: '25'),
      theirs: base.withSchedule(schedule),
    );
    expect(merge.mineChanged, {DiscountPart.value});
    expect(merge.theirsChanged, {DiscountPart.schedule});
    expect(merge.conflicting, isEmpty);
    final merged = merge.resolve(const {});
    expect(merged.percent, '25');
    expect(merged.schedule?.startDate.iso, '2026-12-01');
  });

  test('the same part changed differently needs a choice', () {
    final merge = DiscountMerge(
      base: base,
      mine: base.copyWith(percent: '25'),
      theirs: base.copyWith(percent: '30'),
    );
    expect(merge.conflicting, {DiscountPart.value});
    expect(() => merge.resolve(const {}), throwsStateError);
    expect(merge.resolve({DiscountPart.value: true}).percent, '25');
    expect(merge.resolve({DiscountPart.value: false}).percent, '30');
  });

  test('the same new value on both sides is no conflict', () {
    final merge = DiscountMerge(
      base: base,
      mine: base.copyWith(percent: '25'),
      theirs: base.copyWith(percent: '25.00'),
    );
    expect(merge.conflicting, isEmpty);
  });

  test('values compare normalised', () {
    expect(
      base.copyWith(percent: '20.00').partKey(DiscountPart.value),
      base.partKey(DiscountPart.value),
    );
    expect(
      base.copyWith(minimumQuantity: '5,5').partKey(DiscountPart.minimum),
      base.copyWith(minimumQuantity: '5.5').partKey(DiscountPart.minimum),
    );
  });

  test('the user clearing a part the server kept is applied', () {
    final mine = base.withSchedule(null);
    final withSchedule = base.withSchedule(schedule);
    final merge = DiscountMerge(
      base: withSchedule,
      mine: mine,
      theirs: withSchedule.copyWith(minimumQuantity: '3'),
    );
    final merged = merge.resolve(const {});
    expect(merged.schedule, isNull);
    expect(merged.minimumQuantity, '3');
  });
}
