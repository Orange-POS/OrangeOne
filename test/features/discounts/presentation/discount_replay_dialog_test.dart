import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_replay_dialog.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

void main() {
  const original = DiscountDraft(
    type: DiscountType.percentage,
    percent: '20',
    schedule: DiscountSchedule(
      startDate: LocalDate(2026, 10, 14),
      startTime: TimeOfDayValue(9, 0),
      endDate: LocalDate(2026, 10, 21),
      endTime: TimeOfDayValue(18, 30),
    ),
    minimumQuantity: '3',
  );

  Future<void> pump(WidgetTester tester, DiscountDraft edited) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OrangeTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => DiscountReplayDialog.show(
                context,
                original: original,
                edited: edited,
                currency: 'CHF',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String term(WidgetTester tester, String part) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('discount-replay-$part')),
        matching: find.byType(Text),
      ),
    ))
      text.data!,
  ].join(' | ');

  testWidgets('shows every term of the original offer', (tester) async {
    await pump(tester, original);
    expect(term(tester, 'value'), contains('20% off'));
    expect(term(tester, 'schedule'), contains('Oct 14, 2026 09:00'));
    expect(term(tester, 'schedule'), contains('Oct 21, 2026 18:30'));
    expect(term(tester, 'repeat'), contains('Does Not Repeat'));
    expect(term(tester, 'minimum'), contains('3'));
    expect(find.textContaining('Your edit:'), findsNothing);
    expect(find.text('Retry earlier offer'), findsOneWidget);
  });

  testWidgets('marks only the terms the edit changed', (tester) async {
    await pump(
      tester,
      original.copyWith(
        repeat: const DiscountRepeat(
          RepeatType.weekly,
          weekdays: {Weekday.fri},
        ),
        minimumQuantity: '',
      ),
    );
    expect(term(tester, 'value'), isNot(contains('Your edit')));
    expect(term(tester, 'schedule'), isNot(contains('Your edit')));
    expect(term(tester, 'repeat'), contains('Does Not Repeat'));
    expect(term(tester, 'repeat'), contains('Your edit: Every Fri'));
    expect(term(tester, 'minimum'), contains('Your edit: No Minimum'));
  });
}
