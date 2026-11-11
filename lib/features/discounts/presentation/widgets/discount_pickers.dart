import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:orange_one/core/preferences/time_format_controller.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/orange_switch.dart';

const _border = Color(0xFFDADCE0);

/// The white card that slides up from the bottom for the discount pickers
/// (date, time, repeat): 24 px corners, light border, a gray caption, the
/// content and Cancel / Confirm.
class DiscountSheet extends StatelessWidget {
  const new({
    required this.caption,
    required this.child,
    required this.onConfirm,
    this.confirmKey = const Key('discount-sheet-confirm'),
    super.key,
  });

  final String caption;
  final Widget child;

  /// Null disables Confirm (an incomplete choice).
  final VoidCallback? onConfirm;
  final Key confirmKey;

  /// Slides [sheet] up from the bottom; dismissing it returns null.
  static Future<T?> show<T>(BuildContext context, Widget sheet) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) => sheet,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  caption,
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                child,
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('discount-sheet-cancel'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: shape,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: confirmKey,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: shape,
                        ),
                        onPressed: onConfirm,
                        child: Text(l10n.commonConfirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The month calendar of the design: Monday first, today outlined, the
/// selected day filled orange.
class DiscountDateSheet extends StatefulWidget {
  const new({
    required this.caption,
    required this.initial,
    required this.today,
    this.first,
    this.last,
    this.showYear = true,
    super.key,
  });

  final String caption;
  final DateTime initial;
  final DateTime today;
  final DateTime? first;
  final DateTime? last;

  /// False for an annual date (month and day only).
  final bool showYear;

  static Future<DateTime?> show(
    BuildContext context, {
    required String caption,
    required DateTime initial,
    DateTime? first,
    DateTime? last,
    bool showYear = true,
  }) {
    final now = DateTime.now();
    return DiscountSheet.show<DateTime>(
      context,
      DiscountDateSheet(
        caption: caption,
        initial: initial,
        today: DateTime(now.year, now.month, now.day),
        first: first,
        last: last,
        showYear: showYear,
      ),
    );
  }

  @override
  State<DiscountDateSheet> createState() => _DiscountDateSheetState();
}

class _DiscountDateSheetState extends State<DiscountDateSheet> {
  late DateTime _selected = DateUtils.dateOnly(widget.initial);
  late DateTime _month = DateTime(_selected.year, _selected.month);

  bool _allowed(DateTime day) =>
      (widget.first == null || !day.isBefore(widget.first!)) &&
      (widget.last == null || !day.isAfter(widget.last!));

  bool _monthAllowed(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0);
    return (widget.first == null || !last.isBefore(widget.first!)) &&
        (widget.last == null || !month.isAfter(widget.last!));
  }

  void _shift(int months) {
    final next = DateTime(_month.year, _month.month + months);
    if (_monthAllowed(next)) setState(() => _month = next);
  }

  String _day(String locale, DateTime day) => widget.showYear
      ? DateFormat.yMMMd(locale).format(day)
      : DateFormat.MMMMd(locale).format(day);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    // Empty cells before the 1st (Monday first).
    final lead = DateTime(_month.year, _month.month).weekday - 1;
    final prev = DateTime(_month.year, _month.month - 1);
    final next = DateTime(_month.year, _month.month + 1);
    return DiscountSheet(
      caption: widget.caption,
      confirmKey: const Key('discount-date-confirm'),
      onConfirm: () => Navigator.pop(context, _selected),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('discount-date-previous'),
                tooltip: l10n.discountPreviousMonth,
                color: OrangeTheme.secondary,
                onPressed: _monthAllowed(prev) ? () => _shift(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  (widget.showYear
                          ? DateFormat.yMMMM(locale)
                          : DateFormat.MMMM(locale))
                      .format(_month),
                  key: const Key('discount-date-month'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: OrangeTheme.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const Key('discount-date-next'),
                tooltip: l10n.discountNextMonth,
                color: OrangeTheme.secondary,
                onPressed: _monthAllowed(next) ? () => _shift(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final day in Weekday.values)
                Expanded(
                  child: Text(
                    DiscountText.weekday(locale, day),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: OrangeTheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= days; d++)
                _DayCell(
                  day: DateTime(_month.year, _month.month, d),
                  selected: DateUtils.isSameDay(
                    _selected,
                    DateTime(_month.year, _month.month, d),
                  ),
                  today:
                      widget.showYear &&
                      DateUtils.isSameDay(
                        widget.today,
                        DateTime(_month.year, _month.month, d),
                      ),
                  label: _day(locale, DateTime(_month.year, _month.month, d)),
                  onTap: _allowed(DateTime(_month.year, _month.month, d))
                      ? () => setState(
                          () => _selected = DateTime(
                            _month.year,
                            _month.month,
                            d,
                          ),
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              if (widget.showYear)
                Text(
                  l10n.discountTodayValue(
                    DateFormat.MMMd(locale).format(widget.today),
                  ),
                  style: const TextStyle(color: OrangeTheme.secondary),
                ),
              Text(
                l10n.discountSelectedValue(_day(locale, _selected)),
                key: const Key('discount-date-selected'),
                style: const TextStyle(color: OrangeTheme.secondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const new({
    required this.day,
    required this.selected,
    required this.today,
    required this.label,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: selected ? OrangeTheme.action : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: today && !selected
            ? const BorderSide(color: OrangeTheme.action)
            : BorderSide.none,
      ),
      child: InkWell(
        key: Key('discount-day-${day.day}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 16,
              color: selected
                  ? Colors.white
                  : onTap == null
                  ? _border
                  : OrangeTheme.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The time card: hour and minute wheels that turn by scrolling or with the
/// chevrons, and a switch beside the title between 24-hour (00–23) and
/// 12-hour (12, 01–11 with an AM/PM wheel). The chosen format is remembered
/// on the device ([timeFormatControllerProvider]); the picked value is
/// always a 24-hour [TimeOfDayValue].
class DiscountTimeSheet extends ConsumerStatefulWidget {
  const new({required this.caption, required this.initial, super.key});

  final String caption;
  final TimeOfDayValue initial;

  static Future<TimeOfDayValue?> show(
    BuildContext context, {
    required String caption,
    required TimeOfDayValue initial,
  }) => DiscountSheet.show<TimeOfDayValue>(
    context,
    DiscountTimeSheet(caption: caption, initial: initial),
  );

  @override
  ConsumerState<DiscountTimeSheet> createState() => _DiscountTimeSheetState();
}

class _DiscountTimeSheetState extends ConsumerState<DiscountTimeSheet> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = ref.watch(timeFormatControllerProvider);
    final is24 = format == TimeFormatPreference.hours24;
    final value = TimeOfDayValue(_hour, _minute);
    // The 12-hour wheel shows 12, 01 … 11; AM/PM chooses the half day.
    final hours12 = [
      for (var i = 0; i < 12; i++) (i == 0 ? 12 : i).toString().padLeft(2, '0'),
    ];
    final meridiem = [
      for (final hour in [1, 13])
        DateFormat('a', locale).format(DateTime(2000, 1, 1, hour)),
    ];
    return DiscountSheet(
      caption:
          '${widget.caption} · '
          '${is24 ? l10n.discountTime24 : l10n.discountTime12}',
      confirmKey: const Key('discount-time-confirm'),
      onConfirm: () => Navigator.pop(context, value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.discountSelectTime,
                  style: const TextStyle(
                    color: OrangeTheme.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  l10n.discountTime24Short,
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              OrangeSwitch(
                key: const Key('discount-time-format'),
                value: is24,
                label: l10n.discountTime24,
                onChanged: (on) => ref
                    .read(timeFormatControllerProvider.notifier)
                    .select(
                      on
                          ? TimeFormatPreference.hours24
                          : TimeFormatPreference.hours12,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: is24
                    ? DiscountNumberWheel(
                        // A new key rebuilds the wheel at the same time when
                        // the format changes.
                        key: const ValueKey('hour24'),
                        wheelKey: 'discount-time-hour',
                        label: l10n.discountHour,
                        items: [
                          for (var i = 0; i < 24; i++)
                            i.toString().padLeft(2, '0'),
                        ],
                        value: _hour,
                        onChanged: (hour) => setState(() => _hour = hour),
                      )
                    : DiscountNumberWheel(
                        key: const ValueKey('hour12'),
                        wheelKey: 'discount-time-hour',
                        label: l10n.discountHour,
                        items: hours12,
                        value: _hour % 12,
                        onChanged: (hour) => setState(
                          () => _hour = hour + (_hour >= 12 ? 12 : 0),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DiscountNumberWheel(
                  wheelKey: 'discount-time-minute',
                  label: l10n.discountMinute,
                  items: [
                    for (var i = 0; i < 60; i++) i.toString().padLeft(2, '0'),
                  ],
                  value: _minute,
                  onChanged: (minute) => setState(() => _minute = minute),
                ),
              ),
              if (!is24) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: DiscountNumberWheel(
                    wheelKey: 'discount-time-meridiem',
                    label: l10n.discountMeridiem,
                    items: meridiem,
                    looping: false,
                    value: _hour >= 12 ? 1 : 0,
                    onChanged: (half) =>
                        setState(() => _hour = _hour % 12 + half * 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.discountSelectedValue(
              DiscountText.time(locale, value, format),
            ),
            key: const Key('discount-time-selected'),
            style: const TextStyle(color: OrangeTheme.secondary),
          ),
        ],
      ),
    );
  }
}

/// A wheel of [items] (two-digit numbers, AM/PM): the centre row sits in
/// the pale orange box and is the selection; the chevrons turn it one step.
/// It loops unless [looping] is false.
class DiscountNumberWheel extends StatefulWidget {
  const new({
    required this.wheelKey,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.looping = true,
    super.key,
  });

  final String wheelKey;
  final String label;
  final List<String> items;

  /// Index of the selected item.
  final int value;
  final ValueChanged<int> onChanged;
  final bool looping;

  static const itemExtent = 64.0;

  @override
  State<DiscountNumberWheel> createState() => _DiscountNumberWheelState();
}

class _DiscountNumberWheelState extends State<DiscountNumberWheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.value,
  );

  int get _count => widget.items.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final target = _controller.selectedItem + delta;
    if (!widget.looping && (target < 0 || target >= _count)) return;
    _controller.animateToItem(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const extent = DiscountNumberWheel.itemExtent;
    final children = [
      for (final item in widget.items)
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item,
              style: const TextStyle(
                color: OrangeTheme.dark,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ];
    String at(int index) => widget.items[index % _count];
    final canIncrease = widget.looping || widget.value + 1 < _count;
    final canDecrease = widget.looping || widget.value > 0;
    return Column(
      children: [
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: OrangeTheme.secondary, fontSize: 16),
        ),
        IconButton(
          key: Key('${widget.wheelKey}-up'),
          tooltip: l10n.discountIncrease(widget.label),
          color: OrangeTheme.secondary,
          onPressed: () => _step(1),
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        Semantics(
          label: widget.label,
          value: at(widget.value),
          // A non-looping wheel offers a step only where one exists.
          increasedValue: canIncrease ? at(widget.value + 1) : null,
          decreasedValue: canDecrease ? at(widget.value - 1) : null,
          onIncrease: canIncrease ? () => _step(1) : null,
          onDecrease: canDecrease ? () => _step(-1) : null,
          child: SizedBox(
            height: extent * 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: extent,
                  decoration: BoxDecoration(
                    color: OrangeTheme.pale,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OrangeTheme.action),
                  ),
                ),
                ExcludeSemantics(
                  child: ListWheelScrollView.useDelegate(
                    key: Key(widget.wheelKey),
                    controller: _controller,
                    itemExtent: extent,
                    physics: const FixedExtentScrollPhysics(),
                    diameterRatio: 1.6,
                    perspective: .004,
                    overAndUnderCenterOpacity: .35,
                    onSelectedItemChanged: (index) =>
                        widget.onChanged(index % _count),
                    childDelegate: widget.looping
                        ? ListWheelChildLoopingListDelegate(children: children)
                        : ListWheelChildListDelegate(children: children),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: Key('${widget.wheelKey}-down'),
          tooltip: l10n.discountDecrease(widget.label),
          color: OrangeTheme.secondary,
          onPressed: () => _step(-1),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    );
  }
}
