import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_navigation.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/confirm_dialog.dart';

import '../support/auth_fakes.dart';
import '../support/haptics_fakes.dart';

/// The shared places that play haptics, so no screen needs its own call.
void main() {
  late RecordingHapticEngine engine;
  late MemorySecretStore store;
  setUp(() {
    engine = RecordingHapticEngine();
    store = MemorySecretStore();
  });

  List<Override> overrides() => [
    secretStoreProvider.overrideWithValue(store),
    hapticEngineProvider.overrideWithValue(engine),
  ];

  test('a confirmed product change plays the success haptic', () async {
    final c = ProviderContainer.test(overrides: overrides());
    c
        .read(productSuccessProvider.notifier)
        .show(barcode: '1', title: 'Saved', message: 'Price saved');
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.success]);
    // Dismissing the toast is silent.
    c.read(productSuccessProvider.notifier).dismiss();
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.success]);
  });

  Future<void> mount(
    WidgetTester tester,
    void Function(BuildContext context) onTap,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onTap(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final (name, open) in <(String, void Function(BuildContext))>[
    (
      'product',
      (context) => showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmDialog(title: 'T', message: 'M'),
      ),
    ),
    (
      'discount',
      (context) => confirmDiscountWrite(context, title: 'T', message: 'M'),
    ),
  ]) {
    testWidgets('$name confirmation: Confirm ticks, Cancel is silent', (
      tester,
    ) async {
      await mount(tester, open);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(engine.played, isEmpty);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(engine.played, [HapticEffect.confirm]);
    });
  }

  testWidgets('a confirmed discount result plays the success haptic', (
    tester,
  ) async {
    await mount(tester, (context) => showDiscountResult(context, 'Saved'));
    expect(engine.played, [HapticEffect.success]);
    expect(find.text('Saved'), findsOneWidget);
    // No result (cancelled form) is silent.
    engine.played.clear();
    await mount(tester, (context) => showDiscountResult(context, null));
    expect(engine.played, isEmpty);
  });

  testWidgets('switched off in Settings, nothing plays', (tester) async {
    store.values[hapticsStorageKey] = 'off';
    await mount(tester, (context) => showDiscountResult(context, 'Saved'));
    expect(engine.played, isEmpty);
  });
}
