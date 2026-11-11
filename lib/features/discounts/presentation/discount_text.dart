import 'package:intl/intl.dart';
import 'package:orange_one/core/preferences/time_format_controller.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/l10n/l10n.dart';

/// Localised texts of the discount screens. Titles are built from the typed
/// members (the server `label` is only a fallback), so every language reads
/// the same way.
abstract final class DiscountText {
  static String money(int cents, String currency) =>
      DiscountMoney(cents, currency).display;

  static String typeName(AppLocalizations l10n, DiscountType type) =>
      switch (type) {
        DiscountType.fixedPrice => l10n.discountTypeFixedPrice,
        DiscountType.percentage => l10n.discountTypePercentage,
        DiscountType.collective => l10n.discountTypeCollective,
      };

  static String typeLong(AppLocalizations l10n, DiscountType type) =>
      switch (type) {
        DiscountType.fixedPrice => l10n.discountTypeFixedPriceLong,
        DiscountType.percentage => l10n.discountTypePercentageLong,
        DiscountType.collective => l10n.discountTypeCollectiveLong,
      };

  /// "20% off", "CHF 80.00", "5 for CHF 400.00".
  static String title(AppLocalizations l10n, Discount discount) {
    switch (discount.type) {
      case DiscountType.fixedPrice:
        return discount.fixedPrice?.display ?? discount.label;
      case DiscountType.percentage:
        final percent = discount.percent;
        return percent == null
            ? discount.label
            : l10n.discountPercentOff(_trimPercent(percent));
      case DiscountType.collective:
        final quantity = discount.bundleQuantity;
        final price = discount.bundlePrice;
        return quantity == null || price == null
            ? discount.label
            : l10n.discountBundleOffer('$quantity', price.display);
    }
  }

  static String _trimPercent(String percent) {
    final value = percent.replaceAll(',', '.');
    if (!value.contains('.')) return value;
    final trimmed = value.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// The headline of the live preview.
  static String? previewHeadline(
    AppLocalizations l10n,
    DiscountDraft draft,
    DraftPreview preview,
    String currency,
  ) => switch (draft.type) {
    null => null,
    DiscountType.fixedPrice => money(preview.unitPriceCents!, currency),
    DiscountType.percentage => l10n.discountPercentOff(
      _trimPercent(preview.percent!),
    ),
    DiscountType.collective => l10n.discountBundleOffer(
      '${preview.bundleQuantity}',
      money(preview.bundlePriceCents!, currency),
    ),
  };

  static String status(AppLocalizations l10n, DiscountStatus status) =>
      switch (status) {
        DiscountStatus.active => l10n.discountStatusActive,
        DiscountStatus.scheduled => l10n.discountStatusScheduled,
        DiscountStatus.expired => l10n.discountStatusExpired,
        DiscountStatus.paused => l10n.discountStatusPaused,
        DiscountStatus.archived => l10n.discountStatusArchived,
        DiscountStatus.unknown => l10n.discountStatusUnknown,
      };

  static String date(String locale, LocalDate date) =>
      DateFormat.yMMMd(locale)
          .format(DateTime(date.year, date.month, date.day));

  /// [time] in the user's format: `14:30` or `2:30 PM`.
  static String time(
    String locale,
    TimeOfDayValue time,
    TimeFormatPreference format,
  ) => format == TimeFormatPreference.hours24
      ? time.formatted
      : DateFormat.jm(locale)
            .format(DateTime(2000, 1, 1, time.hour, time.minute));

  static String dateTime(String locale, LocalDate date, TimeOfDayValue time) =>
      '${DiscountText.date(locale, date)} ${time.formatted}';

  /// "14 Oct 2026 09:00 – 21 Oct 2026 09:00", "From 13 Oct 2026 09:00" or
  /// "Not set".
  static String schedule(
    AppLocalizations l10n,
    String locale,
    DiscountSchedule? schedule,
  ) {
    if (schedule == null) return l10n.discountNotSet;
    final start = dateTime(locale, schedule.startDate, schedule.startTime);
    if (!schedule.hasEnd) return l10n.discountFrom(start);
    return l10n.discountRange(
      start,
      dateTime(locale, schedule.endDate!, schedule.endTime!),
    );
  }

  /// The Date & Time card summary: "14 Oct → 21 Oct 2026",
  /// "From 14 Oct 2026" or "Not set".
  static String scheduleShort(
    AppLocalizations l10n,
    String locale,
    DiscountSchedule? schedule,
  ) {
    if (schedule == null) return l10n.discountNotSet;
    if (!schedule.hasEnd) {
      return l10n.discountFrom(date(locale, schedule.startDate));
    }
    final start = schedule.startDate;
    final startText = DateFormat.MMMd(locale)
        .format(DateTime(start.year, start.month, start.day));
    return '$startText → ${date(locale, schedule.endDate!)}';
  }

  static String weekday(String locale, Weekday day) =>
      // 2024-01-01 was a Monday.
      DateFormat.E(locale).format(DateTime(2024, 1, day.iso));

  static String annualDate(String locale, AnnualDate date) =>
      DateFormat.MMMMd(locale).format(DateTime(2023, date.month, date.day));

  static String repeat(
    AppLocalizations l10n,
    String locale,
    DiscountRepeat repeat,
  ) => switch (repeat.type) {
    RepeatType.none => l10n.discountRepeatNone,
    RepeatType.daily => l10n.discountRepeatDaily,
    RepeatType.weekends => l10n.discountRepeatWeekends,
    RepeatType.weekly => l10n.discountRepeatEvery(
      [
        for (final day in Weekday.values)
          if (repeat.weekdays.contains(day)) weekday(locale, day),
      ].join(', '),
    ),
    RepeatType.yearly =>
      repeat.annualDate == null
          ? l10n.discountRepeatYearly
          : l10n.discountYearlyOn(annualDate(locale, repeat.annualDate!)),
  };

  static String minimum(AppLocalizations l10n, String? quantity) =>
      quantity == null || quantity.trim().isEmpty
      ? l10n.discountNoMinimum
      : l10n.discountMinimumItems(_trimPercent(quantity));

  static String issue(AppLocalizations l10n, DiscountIssue issue) =>
      switch (issue) {
        DiscountIssue.required => l10n.discountIssueRequired,
        DiscountIssue.invalidAmount => l10n.discountIssueAmount,
        DiscountIssue.notBelowRegularPrice => l10n.discountIssueBelowRegular,
        DiscountIssue.invalidPercent => l10n.discountIssuePercent,
        DiscountIssue.invalidBundleQuantity => l10n.discountIssueBundleQuantity,
        DiscountIssue.endBeforeStart => l10n.discountIssueEndBeforeStart,
        DiscountIssue.endInPast => l10n.discountIssueEndInPast,
        DiscountIssue.invalidTime => l10n.discountIssueTime,
        DiscountIssue.weekdaysRequired => l10n.discountIssueWeekdays,
        DiscountIssue.invalidAnnualDate => l10n.discountIssueAnnualDate,
        DiscountIssue.invalidQuantity => l10n.discountIssueQuantity,
        DiscountIssue.invalidQuantityStep => l10n.discountIssueQuantityStep,
      };

  /// Texts of rules about the whole discount; null for unknown codes (the
  /// server's message is shown instead).
  static String? rule(AppLocalizations l10n, String? code) => switch (code) {
    'PRODUCT_NOT_DISCOUNTABLE' => l10n.discountNotDiscountable,
    'PRODUCT_PRICE_ZERO' => l10n.discountPriceZero,
    'DISCOUNT_LIMIT_REACHED' => l10n.discountLimitReached,
    'DISCOUNT_ARCHIVED' => l10n.discountArchivedNotice,
    _ => null,
  };
}
