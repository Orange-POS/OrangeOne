import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/l10n/locale_controller.dart';

import '../../support/auth_fakes.dart';
import '../../support/wifi_fakes.dart';

void main() {
  late MemorySecretStore store;
  setUp(() => store = MemorySecretStore());

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        utcNowProvider.overrideWithValue(() => testNow),
        secretStoreProvider.overrideWithValue(store),
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
    return container;
  }

  Finder loginPill() => find.byKey(const Key('language-selector'));
  Finder settingsRow() => find.byKey(const Key('settings-language'));

  Future<void> choose(WidgetTester tester, Finder menu, String code) async {
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('language-$code')).last);
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
  }

  testWidgets('Settings show the current language with the same greeting', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    expect(
      find.descendant(of: settingsRow(), matching: find.text('Hello')),
      findsOneWidget,
    );
    expect(find.text('Language'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('Language: English')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('a choice in Settings applies everywhere and is saved', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await openSettings(tester);
    await choose(tester, settingsRow(), 'nl');

    // Settings themselves switch at once.
    expect(find.text('Instellingen'), findsOneWidget);
    expect(find.text('Taal'), findsOneWidget);
    expect(
      find.descendant(of: settingsRow(), matching: find.text('Hallo')),
      findsOneWidget,
    );
    expect(container.read(localeControllerProvider), const Locale('nl'));
    expect(await store.read(localeStorageKey), 'nl');

    // The login badge shows the same language.
    await back(tester);
    expect(
      find.descendant(of: loginPill(), matching: find.text('Hallo')),
      findsOneWidget,
    );
  });

  testWidgets('a choice on the login badge shows in Settings', (tester) async {
    await pumpApp(tester);
    await choose(tester, loginPill(), 'fr');
    await openSettings(tester);
    expect(
      find.descendant(of: settingsRow(), matching: find.text('Bonjour')),
      findsOneWidget,
    );
    expect(find.text('Paramètres'), findsWidgets);

    // And back again from Settings, in both directions, twice.
    await choose(tester, settingsRow(), 'ta');
    await back(tester);
    expect(
      find.descendant(of: loginPill(), matching: find.text('வணக்கம்')),
      findsOneWidget,
    );
    await choose(tester, loginPill(), 'en');
    await openSettings(tester);
    expect(
      find.descendant(of: settingsRow(), matching: find.text('Hello')),
      findsOneWidget,
    );
    expect(await store.read(localeStorageKey), 'en');
  });

  testWidgets('a saved language is shown by both after a restart', (
    tester,
  ) async {
    await store.write(localeStorageKey, 'it');
    await pumpApp(tester);
    expect(
      find.descendant(of: loginPill(), matching: find.text('Ciao')),
      findsOneWidget,
    );
    await openSettings(tester);
    expect(
      find.descendant(of: settingsRow(), matching: find.text('Ciao')),
      findsOneWidget,
    );
  });
}
