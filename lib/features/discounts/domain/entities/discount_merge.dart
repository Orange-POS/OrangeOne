import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';

/// The independently editable parts of a discount. A concurrent change is
/// merged part by part: a part only one side changed keeps that side's
/// value; a part both sides changed differently needs the user's choice.
enum DiscountPart {
  /// Type and its value (fixed price, percent, bundle quantity and price).
  value,
  schedule,
  repeat,
  minimum,
}

/// Normalised values of a draft, so "20" and "20.00" or "5,5" and "5.5"
/// compare equal.
extension DiscountDraftParts on DiscountDraft {
  static String _decimal(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    final cents = DiscountMoney.parseCents(value);
    return cents?.toString() ?? value;
  }

  static String _weekdays(DiscountRepeat repeat) => [
    for (final day in Weekday.values)
      if (repeat.weekdays.contains(day)) day.name,
  ].join(',');

  /// A comparable fingerprint of [part].
  String partKey(DiscountPart part) => switch (part) {
    DiscountPart.value => switch (type) {
      null => '',
      DiscountType.fixedPrice => 'fixed ${_decimal(fixedPrice)}',
      DiscountType.percentage => 'percent ${_decimal(percent)}',
      DiscountType.collective =>
        'bundle ${bundleQuantity.trim()} ${_decimal(bundlePrice)}',
    },
    DiscountPart.schedule =>
      schedule == null
          ? ''
          : '${schedule!.startDate.iso} ${schedule!.startTime.formatted} '
                '${schedule!.endDate?.iso} ${schedule!.endTime?.formatted}',
    DiscountPart.repeat =>
      '${repeat.type.name} ${_weekdays(repeat)} '
          '${repeat.annualDate?.month}-${repeat.annualDate?.day}',
    DiscountPart.minimum => _decimal(minimumQuantity),
  };

  /// This draft with [part] taken from [other].
  DiscountDraft withPartFrom(DiscountPart part, DiscountDraft other) =>
      switch (part) {
        DiscountPart.value => DiscountDraft(
          type: other.type,
          fixedPrice: other.fixedPrice,
          percent: other.percent,
          bundleQuantity: other.bundleQuantity,
          bundlePrice: other.bundlePrice,
          schedule: schedule,
          repeat: repeat,
          minimumQuantity: minimumQuantity,
        ),
        DiscountPart.schedule => withSchedule(other.schedule),
        DiscountPart.repeat => copyWith(repeat: other.repeat),
        DiscountPart.minimum => copyWith(
          minimumQuantity: other.minimumQuantity,
        ),
      };
}

/// A three-way merge after `VERSION_CONFLICT`: `base` is the version the
/// user started from, `mine` the user's draft, `theirs` the latest server
/// version.
class DiscountMerge {
  factory({
    required DiscountDraft base,
    required DiscountDraft mine,
    required DiscountDraft theirs,
  }) {
    Set<DiscountPart> changed(DiscountDraft draft) => {
      for (final part in DiscountPart.values)
        if (draft.partKey(part) != base.partKey(part)) part,
    };
    return DiscountMerge._(
      mine: mine,
      theirs: theirs,
      mineChanged: changed(mine),
      theirsChanged: changed(theirs),
    );
  }

  const new _({
    required this.mine,
    required this.theirs,
    required this.mineChanged,
    required this.theirsChanged,
  });

  final DiscountDraft mine;
  final DiscountDraft theirs;

  /// Parts the user changed.
  final Set<DiscountPart> mineChanged;

  /// Parts changed on the server meanwhile.
  final Set<DiscountPart> theirsChanged;

  /// Parts both sides changed to different values: the user must choose.
  Set<DiscountPart> get conflicting => {
    for (final part in mineChanged.intersection(theirsChanged))
      if (mine.partKey(part) != theirs.partKey(part)) part,
  };

  /// The merged draft: the server's version with the user's own changes,
  /// and for each conflicting part the side in [keepMine] (`true` = the
  /// user's value). Every conflicting part must be decided.
  DiscountDraft resolve(Map<DiscountPart, bool> keepMine) {
    final open = conflicting.difference(keepMine.keys.toSet());
    if (open.isNotEmpty) {
      throw StateError('Undecided parts: $open');
    }
    var merged = theirs;
    for (final part in mineChanged) {
      final useMine = !conflicting.contains(part) || keepMine[part]!;
      if (useMine) merged = merged.withPartFrom(part, mine);
    }
    return merged;
  }
}
