import 'dart:async';

import 'package:flutter/material.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_form_inputs.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_pickers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

const _border = Color(0xFFDADCE0);

/// A card of the form (Date & Time, Minimum Quantity, Repeat Schedule):
/// icon, title and summary, and a chevron. [child] slides open and closed
/// smoothly below the header; once open, the card scrolls itself to the
/// middle of the visible area, so nothing stays hidden under the sticky
/// action bar. Without a child the card only reports taps (Repeat Schedule
/// opens its sheet).
class DiscountSection extends StatefulWidget {
  const new({
    required this.sectionKey,
    required this.icon,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    this.child,
    this.error,
    super.key,
  });

  static const duration = Duration(milliseconds: 280);
  static const chevron = 'assets/icons/settings_chevron_down.svg';

  final String sectionKey;

  /// SVG asset of the leading icon.
  final String icon;
  final String title;
  final String summary;
  final bool expanded;
  final VoidCallback? onToggle;
  final Widget? child;
  final String? error;

  @override
  State<DiscountSection> createState() => _DiscountSectionState();
}

class _DiscountSectionState extends State<DiscountSection> {
  Timer? _reveal;

  @override
  void didUpdateWidget(DiscountSection old) {
    super.didUpdateWidget(old);
    if (widget.child != null && widget.expanded && !old.expanded) {
      // After the card has opened: bring it to the middle of the visible
      // area (above the sticky action bar).
      _reveal?.cancel();
      _reveal = Timer(DiscountSection.duration, () {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      });
    } else if (!widget.expanded) {
      _reveal?.cancel();
    }
  }

  @override
  void dispose() {
    _reveal?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: DiscountPanel(
      padding: EdgeInsets.zero,
      radius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: widget.child == null ? null : widget.expanded,
            child: InkWell(
              key: Key(widget.sectionKey),
              onTap: widget.onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      DiscountSvgIcon(widget.icon, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: OrangeTheme.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.summary,
                              style: const TextStyle(
                                color: OrangeTheme.secondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: widget.expanded ? .5 : 0,
                        duration: DiscountSection.duration,
                        curve: Curves.easeInOut,
                        child: const DiscountSvgIcon(
                          DiscountSection.chevron,
                          color: OrangeTheme.secondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.child != null)
            ClipRect(
              child: AnimatedSize(
                duration: DiscountSection.duration,
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: widget.expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: widget.child,
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                widget.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A tappable value box of the design (date, time, annual date): 12 px
/// corners, light border; it opens a picker.
class DiscountPickerField extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.value,
    required this.onTap,
    this.label,
    super.key,
  });

  final String fieldKey;
  final String? label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label != null) ...[
        Text(
          label!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: OrangeTheme.ink,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _border),
          ),
          child: InkWell(
            key: Key(fieldKey),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 17,
                      color: onTap == null
                          ? OrangeTheme.secondary
                          : OrangeTheme.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// The Repeat Schedule card that slides up: the repeat options, weekdays
/// and the annual date.
class DiscountRepeatSheet extends StatefulWidget {
  const new({required this.initial, super.key});
  final DiscountRepeat initial;

  static Future<DiscountRepeat?> show(
    BuildContext context,
    DiscountRepeat initial,
  ) => DiscountSheet.show<DiscountRepeat>(
    context,
    DiscountRepeatSheet(initial: initial),
  );

  @override
  State<DiscountRepeatSheet> createState() => _DiscountRepeatSheetState();
}

class _DiscountRepeatSheetState extends State<DiscountRepeatSheet> {
  late RepeatType _type = widget.initial.type;
  late final Set<Weekday> _days = {...widget.initial.weekdays};
  late AnnualDate? _annual = widget.initial.annualDate;

  bool get _valid => switch (_type) {
    RepeatType.weekly => _days.isNotEmpty,
    RepeatType.yearly => _annual?.valid ?? false,
    _ => true,
  };

  Future<void> _pickAnnual() async {
    final now = DateTime.now();
    final l10n = context.l10n;
    // A non-leap year: 29 February cannot be chosen.
    final picked = await DiscountDateSheet.show(
      context,
      caption: l10n.discountEditingField(l10n.discountAnnualDate),
      first: DateTime(2023),
      last: DateTime(2023, 12, 31),
      showYear: false,
      initial: DateTime(
        2023,
        _annual?.month ?? now.month,
        _annual?.day ?? (now.month == 2 && now.day == 29 ? 28 : now.day),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _annual = AnnualDate(picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final options = [
      (RepeatType.none, l10n.discountRepeatNone, null),
      (RepeatType.daily, l10n.discountRepeatDaily, null),
      (RepeatType.weekly, l10n.discountRepeatWeekly, null),
      (
        RepeatType.weekends,
        l10n.discountRepeatWeekends,
        l10n.discountRepeatWeekendsHint,
      ),
      (RepeatType.yearly, l10n.discountRepeatYearly, null),
    ];
    return DiscountSheet(
      caption: l10n.discountEditingField(l10n.discountRepeatSchedule),
      confirmKey: const Key('discount-repeat-apply'),
      onConfirm: _valid
          ? () => Navigator.pop(
              context,
              DiscountRepeat(
                _type,
                weekdays: _type == RepeatType.weekly ? {..._days} : {},
                annualDate: _type == RepeatType.yearly ? _annual : null,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.discountRepeatSchedule,
            style: const TextStyle(
              color: OrangeTheme.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final (type, title, hint) in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RepeatOption(
                key: Key('discount-repeat-${type.name}'),
                title: title,
                hint: hint,
                selected: _type == type,
                onTap: () => setState(() => _type = type),
              ),
            ),
          AnimatedSize(
            duration: DiscountSection.duration,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_type == RepeatType.weekly) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.discountRepeatOn,
                    style: const TextStyle(color: OrangeTheme.secondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final day in Weekday.values) ...[
                        if (day != Weekday.values.first)
                          const SizedBox(width: 4),
                        Expanded(
                          child: _DayChip(
                            key: Key('discount-weekday-${day.name}'),
                            label: DiscountText.weekday(locale, day),
                            selected: _days.contains(day),
                            onTap: () => setState(
                              () => _days.contains(day)
                                  ? _days.remove(day)
                                  : _days.add(day),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_days.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.discountIssueWeekdays,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
                if (_type == RepeatType.yearly) ...[
                  const SizedBox(height: 4),
                  DiscountPickerField(
                    fieldKey: 'discount-annual-date',
                    label: l10n.discountAnnualDate,
                    value: _annual == null
                        ? l10n.discountChooseAnnualDate
                        : DiscountText.annualDate(locale, _annual!),
                    onTap: _pickAnnual,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepeatOption extends StatelessWidget {
  const new({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: Material(
      color: selected ? OrangeTheme.pale : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? OrangeTheme.action : _border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected ? OrangeTheme.dark : OrangeTheme.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (hint != null)
                        Text(
                          hint!,
                          style: const TextStyle(
                            color: OrangeTheme.secondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(
                    Icons.check_circle,
                    color: OrangeTheme.action,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DayChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? OrangeTheme.action : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? OrangeTheme.action : _border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : OrangeTheme.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
