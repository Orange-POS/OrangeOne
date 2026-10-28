import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';

import '../support/auth_fakes.dart';

void main() {
  late MemorySecretStore store;
  ProviderContainer newContainer([SecretStore? override]) =>
      ProviderContainer.test(
        overrides: [secretStoreProvider.overrideWithValue(override ?? store)],
      )..listen(localeControllerProvider, (_, _) {});
  setUp(() => store = MemorySecretStore());

  test('offers exactly the six languages, all supported by the app', () {
    expect(appLanguages.map((l) => l.locale.languageCode), [
      'en',
      'nl',
      'fr',
      'it',
      'tr',
      'ta',
    ]);
    expect(appLanguages.map((l) => l.greeting), [
      'Hello',
      'Hallo',
      'Bonjour',
      'Ciao',
      'Merhaba',
      'வணக்கம்',
    ]);
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      appLanguages.map((l) => l.locale.languageCode).toSet(),
    );
  });

  test('follows the device language until a language is chosen', () async {
    final container = newContainer();
    expect(container.read(localeControllerProvider), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(localeControllerProvider), isNull);
  });

  test('restores the saved language at startup', () async {
    store.values[localeStorageKey] = 'fr';
    final container = newContainer();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(localeControllerProvider), const Locale('fr'));
  });

  for (final saved in ['es', '', 'nl-BE', 'xx']) {
    test('ignores an unsupported saved value "$saved"', () async {
      store.values[localeStorageKey] = saved;
      final container = newContainer();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(localeControllerProvider), isNull);
    });
  }

  test('a choice applies at once and is saved', () async {
    final container = newContainer();
    final saving = container
        .read(localeControllerProvider.notifier)
        .select(const Locale('ta'));
    expect(container.read(localeControllerProvider), const Locale('ta'));
    await saving;
    expect(store.values[localeStorageKey], 'ta');
    // A new run of the app starts with the saved language.
    final restarted = newContainer();
    await Future<void>.delayed(Duration.zero);
    expect(restarted.read(localeControllerProvider), const Locale('ta'));
  });

  test('a language chosen while restoring wins over the stored one', () async {
    store.values[localeStorageKey] = 'it';
    final container = newContainer();
    await container
        .read(localeControllerProvider.notifier)
        .select(const Locale('tr'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(localeControllerProvider), const Locale('tr'));
    expect(store.values[localeStorageKey], 'tr');
  });

  test('regional locales map to their language; others are ignored', () async {
    final container = newContainer();
    final notifier = container.read(localeControllerProvider.notifier);
    await notifier.select(const Locale('es'));
    expect(container.read(localeControllerProvider), isNull);
    expect(store.writes, 0);
    await notifier.select(const Locale('fr', 'CH'));
    expect(container.read(localeControllerProvider), const Locale('fr'));
    expect(store.values[localeStorageKey], 'fr');
  });

  test('storage failures never block the language', () async {
    store.failure = storageFailure;
    final container = newContainer();
    await Future<void>.delayed(Duration.zero);
    await container
        .read(localeControllerProvider.notifier)
        .select(const Locale('nl'));
    expect(container.read(localeControllerProvider), const Locale('nl'));
    expect(store.values, isEmpty);
  });

  test('a disposed controller does not fail on a late restore', () async {
    final pending = Completer<void>();
    store.values[localeStorageKey] = 'fr';
    final slow = _SlowStore(store, pending.future);
    ProviderContainer(overrides: [secretStoreProvider.overrideWithValue(slow)])
      ..listen(localeControllerProvider, (_, _) {})
      ..dispose();
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 0);
  });

  test('every language translates every message', () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    for (final language in appLanguages) {
      final l10n = await AppLocalizations.delegate.load(language.locale);
      final texts = [
        l10n.loginScanTitle,
        l10n.loginSubtitle,
        l10n.loginScanSemantics,
        l10n.loginSessionExpired,
        l10n.loginRestoringSemantics,
        l10n.loginRestoreFailed,
        l10n.loginRetryRestore,
        l10n.languageSelectorLabel,
        l10n.languageSelectorTooltip,
        l10n.languageSelectorSemantics('X'),
        l10n.scanTitle,
        l10n.scanBackTooltip,
        l10n.scanHeading,
        l10n.scanInstruction,
        l10n.scanSigningIn,
        l10n.scanFailure,
        l10n.scanAgain,
        l10n.scanVerifying,
        l10n.scanPausedError,
        l10n.scanOpeningCamera,
        l10n.scanCheckingWifi,
        l10n.scanWifiRequired,
        l10n.scanWifiStatus,
        l10n.cameraReady,
        l10n.cameraAllowInstructions,
        l10n.cameraPermissionRequired,
        l10n.cameraUnavailable,
        l10n.cameraPaused,
        l10n.cameraBusy,
        l10n.cameraOpenFailed,
        l10n.cameraTryAgain,
        l10n.cameraRestricted,
        l10n.cameraOpenSettings,
        l10n.cameraAllowRetry,
      ];
      expect(texts.every((text) => text.trim().isNotEmpty), isTrue);
      expect(l10n.languageSelectorSemantics('X'), contains('X'));
      if (language.locale.languageCode != 'en') {
        expect(l10n.scanWifiRequired, isNot(english.scanWifiRequired));
        expect(l10n.loginScanTitle, isNot(english.loginScanTitle));
      }
    }
    expect(
      english.scanWifiRequired,
      'Please connect to the same Wi-Fi network as the POS machine '
      'to scan the QR code.',
    );
  });
}

class _SlowStore implements SecretStore {
  const new(this._inner, this._ready);
  final SecretStore _inner;
  final Future<void> _ready;

  @override
  Future<String?> read(String key) async {
    await _ready;
    return await _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);
}
