import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/confirm_dialog.dart';

import '../support/haptics_fakes.dart';

void main() {
  late RecordingHapticEngine engine;
  setUp(() => engine = RecordingHapticEngine());

  Future<List<bool>> open(
    WidgetTester tester, {
    bool outlinedCancel = false,
  }) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: hapticsOverrides(engine),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await ConfirmDialog.show(
                  context,
                  title: 'Save?',
                  message: 'Name: Tea',
                  outlinedCancel: outlinedCancel,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('Confirm answers true once and plays the confirm haptic', (
    tester,
  ) async {
    final answers = await open(tester);
    expect(find.text('Save?'), findsOneWidget);
    expect(find.text('Name: Tea'), findsOneWidget);
    // A second tap while the dialog closes is ignored.
    await tester.tap(find.text('Confirm'));
    await tester.tap(find.text('Confirm'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(answers, [true]);
    expect(engine.played, [HapticEffect.confirm]);
  });

  testWidgets('Cancel and dismissing answer false without a haptic', (
    tester,
  ) async {
    final answers = await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(answers, [false, false]);
    expect(engine.played, isEmpty);
  });

  testWidgets('the product and discount designs of Cancel', (tester) async {
    await open(tester);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(tester, outlinedCancel: true);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
  });
}
