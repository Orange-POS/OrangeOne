import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/wifi_fakes.dart';

void main() {
  late MemorySecretStore store;
  setUp(() => store = MemorySecretStore());

  Future<ProviderContainer> pumpLogin(WidgetTester tester) async {
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

  Finder selector() => find.byKey(const Key('language-selector'));
  Finder item(String code) => find.byKey(Key('language-$code'));

  Future<void> choose(WidgetTester tester, String code) async {
    await tester.tap(selector());
    await tester.pumpAndSettle();
    await tester.tap(item(code));
    await tester.pumpAndSettle();
  }

  Future<AppLocalizations> strings(String code) =>
      AppLocalizations.delegate.load(Locale(code));

  testWidgets('login shows the pill and the existing content in English', (
    tester,
  ) async {
    await pumpLogin(tester);
    expect(
      find.descendant(of: selector(), matching: find.text('Hello')),
      findsOneWidget,
    );
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(find.text('Sign in with your POS machine'), findsOneWidget);
    expect(find.text('Powered By OrangeONE'), findsOneWidget);
    expect(find.byKey(const Key('scan-login-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pill keeps a 48 point touch target', (tester) async {
    await pumpLogin(tester);
    final size = tester.getSize(selector());
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(150));
    // A compact pill, not a full-width bar.
    expect(size.width, lessThan(220));
  });

  testWidgets('the menu lists the six languages by greeting', (tester) async {
    await pumpLogin(tester);
    await tester.tap(selector());
    await tester.pumpAndSettle();
    for (final language in appLanguages) {
      expect(
        find.descendant(
          of: item(language.locale.languageCode),
          matching: find.text(language.greeting),
        ),
        findsOneWidget,
      );
    }
    expect(find.byType(PopupMenuItem<AppLanguage>), findsNWidgets(6));
    // Dismissing the menu changes nothing.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(store.writes, 0);
  });

  for (final language in appLanguages) {
    final code = language.locale.languageCode;
    testWidgets('selecting ${language.name} translates the login screen', (
      tester,
    ) async {
      await pumpLogin(tester);
      // Start from a different language so every choice is a real change.
      if (code == 'en') await choose(tester, 'nl');
      await choose(tester, code);
      final l10n = await strings(code);
      expect(find.text(l10n.loginScanTitle), findsOneWidget);
      expect(find.text(l10n.loginSubtitle), findsOneWidget);
      expect(
        find.descendant(of: selector(), matching: find.text(language.greeting)),
        findsOneWidget,
      );
      expect(store.values[localeStorageKey], code);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the scanner screen follows the selected language', (
    tester,
  ) async {
    await pumpLogin(tester);
    await choose(tester, 'nl');
    await tester.tap(find.byKey(const Key('scan-login-button')));
    await tester.pumpAndSettle();
    final l10n = await strings('nl');
    expect(find.text(l10n.scanTitle), findsOneWidget);
    expect(find.text(l10n.scanHeading), findsOneWidget);
    expect(find.text(l10n.scanInstruction), findsOneWidget);
    expect(find.byTooltip(l10n.scanBackTooltip), findsOneWidget);
    expect(find.text('Scan QR Code'), findsNothing);
  });

  testWidgets('the language stays selected after restarting the app', (
    tester,
  ) async {
    await pumpLogin(tester);
    await choose(tester, 'ta');
    await tester.pumpWidget(const SizedBox.shrink());
    // A new run with the same device storage.
    await pumpLogin(tester);
    final l10n = await strings('ta');
    expect(find.text(l10n.loginScanTitle), findsOneWidget);
    expect(
      find.descendant(of: selector(), matching: find.text('வணக்கம்')),
      findsOneWidget,
    );
  });

  testWidgets('a saved language wins over the device language', (tester) async {
    store.values[localeStorageKey] = 'fr';
    tester.platformDispatcher.localesTestValue = const [Locale('tr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpLogin(tester);
    expect(find.text((await strings('fr')).loginScanTitle), findsOneWidget);
  });

  testWidgets('without a choice the device language is used if supported', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('tr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpLogin(tester);
    expect(find.text((await strings('tr')).loginScanTitle), findsOneWidget);
    expect(
      find.descendant(of: selector(), matching: find.text('Merhaba')),
      findsOneWidget,
    );
  });

  testWidgets('an unsupported device language falls back to English', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpLogin(tester);
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(
      find.descendant(of: selector(), matching: find.text('Hello')),
      findsOneWidget,
    );
  });

  testWidgets('screen readers get the language name and a tooltip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpLogin(tester);
    expect(find.bySemanticsLabel(RegExp('Language: English')), findsWidgets);
    await choose(tester, 'tr');
    expect(find.bySemanticsLabel(RegExp('Dil: Türkçe')), findsWidgets);
    await tester.tap(selector());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Nederlands'), findsOneWidget);
    expect(find.bySemanticsLabel('தமிழ்'), findsOneWidget);
    handle.dispose();
  });

  for (final language in appLanguages) {
    testWidgets('login fits a small phone in ${language.name}', (tester) async {
      store.values[localeStorageKey] = language.locale.languageCode;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLogin(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(selector());
      await tester.pumpAndSettle();
      await tester.tap(selector());
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<AppLanguage>), findsNWidgets(6));
      expect(tester.takeException(), isNull);
    });
  }
}
