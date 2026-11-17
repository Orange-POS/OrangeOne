import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/widgets/orange_switch.dart';

import '../../support/auth_fakes.dart';
import '../../support/haptics_fakes.dart';
import '../../support/wifi_fakes.dart';

void main() {
  late MemorySecretStore store;
  setUp(() => store = MemorySecretStore());

  Future<ProviderContainer> openSettings(WidgetTester tester) async {
    final container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        utcNowProvider.overrideWithValue(() => testNow),
        secretStoreProvider.overrideWithValue(store),
        hapticEngineProvider.overrideWithValue(RecordingHapticEngine()),
        wifiConnected,
        qrCameraBuilderProvider.overrideWithValue(
          (context, onCode, onStatus) => const SizedBox(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    return container;
  }

  Finder toggle() => find.byKey(const Key('settings-haptics-switch'));
  bool switchOn(WidgetTester tester) =>
      tester.widget<OrangeSwitch>(toggle()).value;

  testWidgets('the Haptic feedback switch is on and turns haptics off', (
    tester,
  ) async {
    final container = await openSettings(tester);
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(switchOn(tester), isTrue);
    await tester.ensureVisible(toggle());
    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(container.read(hapticsControllerProvider), isFalse);
    expect(store.values[hapticsStorageKey], 'off');
    expect(switchOn(tester), isFalse);
  });

  testWidgets('a stored "off" shows the switch off', (tester) async {
    store.values[hapticsStorageKey] = 'off';
    await openSettings(tester);
    expect(switchOn(tester), isFalse);
  });

  for (final language in appLanguages) {
    testWidgets('the switch is translated to ${language.name}', (tester) async {
      store.values[localeStorageKey] = language.locale.languageCode;
      await openSettings(tester);
      final l10n = await AppLocalizations.delegate.load(language.locale);
      expect(find.text(l10n.settingsHapticsLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
