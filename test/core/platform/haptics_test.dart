import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/core/storage/secret_store.dart';

import '../../support/auth_fakes.dart';
import '../../support/haptics_fakes.dart';

void main() {
  late MemorySecretStore store;
  late RecordingHapticEngine engine;

  var now = Duration.zero;

  ProviderContainer container() => ProviderContainer.test(
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      hapticEngineProvider.overrideWithValue(engine),
      hapticClockProvider.overrideWithValue(() => now),
    ],
  );

  setUp(() {
    store = MemorySecretStore();
    engine = RecordingHapticEngine();
    now = Duration.zero;
  });

  test('a fast wheel spin ticks per value, never faster than 40 ms', () async {
    final haptics = container().read(hapticsControllerProvider.notifier)
      ..play(HapticEffect.selection)
      ..play(HapticEffect.selection);
    now += const Duration(milliseconds: 40);
    haptics.play(HapticEffect.selection);
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.selection, HapticEffect.selection]);
  });

  test('one failure vibrates once, also when reported twice', () async {
    final haptics = container().read(hapticsControllerProvider.notifier)
      ..play(HapticEffect.error)
      ..play(HapticEffect.error);
    now += const Duration(milliseconds: 999);
    haptics.play(HapticEffect.error);
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.error]);
    // A later failure vibrates again; other effects are never held back.
    now += const Duration(seconds: 1);
    haptics
      ..play(HapticEffect.error)
      ..play(HapticEffect.success)
      ..play(HapticEffect.success);
    await pumpEventQueue();
    expect(engine.played, [
      HapticEffect.error,
      HapticEffect.error,
      HapticEffect.success,
      HapticEffect.success,
    ]);
  });

  test('only a validation refusal plays the error haptic', () async {
    final haptics = container().read(hapticsControllerProvider.notifier);
    for (final kind in FailureKind.values.where(
      (kind) => kind != FailureKind.validation,
    )) {
      haptics.rejected(AppFailure(kind, 'x'));
    }
    haptics.rejected(const FormatException('x'));
    await pumpEventQueue();
    expect(engine.played, isEmpty);
    haptics.rejected(const AppFailure(FailureKind.validation, 'Invalid'));
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.error]);
  });

  test('on until the user switches it off, and then it stays silent', () async {
    final c = container();
    expect(c.read(hapticsControllerProvider), isTrue);
    c.read(hapticsControllerProvider.notifier).play(HapticEffect.success);
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.success]);

    await c.read(hapticsControllerProvider.notifier).select(enabled: false);
    c.read(hapticsControllerProvider.notifier).play(HapticEffect.scan);
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.success]);
    expect(store.values[hapticsStorageKey], 'off');
  });

  test('a stored "off" is restored on the next start', () async {
    store.values[hapticsStorageKey] = 'off';
    final c = container()..listen(hapticsControllerProvider, (_, _) {});
    await pumpEventQueue();
    expect(c.read(hapticsControllerProvider), isFalse);
  });

  test('a storage failure never blocks the choice', () async {
    store.failure = const AppFailure(FailureKind.storage, 'unavailable');
    final c = container();
    await c.read(hapticsControllerProvider.notifier).select(enabled: false);
    expect(c.read(hapticsControllerProvider), isFalse);
  });

  test('a device without haptics stays silent instead of failing', () async {
    engine.failure = PlatformException(code: 'unavailable');
    final c = container();
    c.read(hapticsControllerProvider.notifier).play(HapticEffect.confirm);
    await pumpEventQueue();
    expect(engine.played, [HapticEffect.confirm]);
  });

  test('the platform engine sends the matching system haptic', () async {
    final calls = <Object?>[];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call.arguments);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const platform = PlatformHapticEngine();
    for (final effect in HapticEffect.values) {
      await platform.play(effect);
    }
    expect(calls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.selectionClick',
      // Not iOS in tests: Android's heavy tap.
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets('playHaptic plays through the scope, silent without one', (
    tester,
  ) async {
    late BuildContext inside;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secretStoreProvider.overrideWithValue(store),
          hapticEngineProvider.overrideWithValue(engine),
        ],
        child: Builder(
          builder: (context) {
            inside = context;
            return const SizedBox();
          },
        ),
      ),
    );
    playHaptic(inside, HapticEffect.scan);
    await tester.pump();
    expect(engine.played, [HapticEffect.scan]);

    late BuildContext outside;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          outside = context;
          return const SizedBox();
        },
      ),
    );
    playHaptic(outside, HapticEffect.scan);
    await tester.pump();
    expect(engine.played, [HapticEffect.scan]);
  });
}
