import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_form_sections.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/validation_haptic.dart';

import '../support/haptics_fakes.dart';

void main() {
  late RecordingHapticEngine engine;
  late List<Override> overrides;
  setUp(() {
    engine = RecordingHapticEngine();
    // Once per test: the fake clock keeps running across pumps.
    overrides = hapticsOverrides(engine);
  });

  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );

  Future<void> field(WidgetTester tester, String? error) =>
      show(tester, ValidationHaptic(error: error, child: const TextField()));

  testWidgets('plays once when the error appears, not while it stays', (
    tester,
  ) async {
    await field(tester, null);
    await field(tester, 'Enter a value above zero');
    await tester.pump();
    expect(engine.played, [HapticEffect.error]);
    // Rebuilds and a changed message of the same failure stay silent.
    await field(tester, 'Enter a value above zero');
    await field(tester, 'Enter at most 100');
    await tester.pump();
    expect(engine.played, [HapticEffect.error]);
    // Fixed, then wrong again: a new failure.
    await field(tester, null);
    await field(tester, 'Enter at most 100');
    await tester.pump();
    expect(engine.played, [HapticEffect.error, HapticEffect.error]);
  });

  testWidgets('a screen opening with an error is silent', (tester) async {
    await field(tester, 'Required');
    await field(tester, 'Required');
    await tester.pump();
    expect(engine.played, isEmpty);
  });

  testWidgets('the child is shown unchanged', (tester) async {
    await field(tester, 'Required');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ValidationHaptic), findsOneWidget);
  });

  group('form card (Date & Time, Minimum Quantity, Repeat)', () {
    Future<void> card(
      WidgetTester tester, {
      required bool expanded,
      String? error,
    }) => show(
      tester,
      DiscountSection(
        sectionKey: 'card',
        icon: 'assets/icons/discount_calendar.svg',
        title: 'Date & Time',
        summary: 'Today',
        expanded: expanded,
        onToggle: () {},
        error: error,
      ),
    );

    testWidgets('its error appearing vibrates once', (tester) async {
      await card(tester, expanded: false);
      await card(tester, expanded: false, error: 'End before start');
      await card(tester, expanded: false, error: 'End before start');
      await tester.pump();
      expect(engine.played, [HapticEffect.error]);
    });

    testWidgets('opening or closing the card never vibrates', (tester) async {
      // The Minimum Quantity card shows its error only while closed; the
      // open input shows it instead. Closing moves it back: no new failure.
      await card(tester, expanded: true);
      await card(tester, expanded: false, error: 'Enter a whole number');
      await tester.pump();
      expect(engine.played, isEmpty);
    });
  });
}
