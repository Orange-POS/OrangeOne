import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/storage/secret_store.dart';

/// A language offered in the language selector. The [greeting] is shown in
/// the selector and [name] is the language's own name for screen readers.
class AppLanguage {
  const new(this.locale, this.greeting, this.name);
  final Locale locale;
  final String greeting;
  final String name;
}

/// The six supported languages, in selector order.
const appLanguages = [
  AppLanguage(Locale('en'), 'Hello', 'English'),
  AppLanguage(Locale('nl'), 'Hallo', 'Nederlands'),
  AppLanguage(Locale('fr'), 'Bonjour', 'Français'),
  AppLanguage(Locale('it'), 'Ciao', 'Italiano'),
  AppLanguage(Locale('tr'), 'Merhaba', 'Türkçe'),
  AppLanguage(Locale('ta'), 'வணக்கம்', 'தமிழ்'),
];

/// The language for [code], or null when it is not supported.
AppLanguage? appLanguageFor(String? code) {
  for (final language in appLanguages) {
    if (language.locale.languageCode == code) return language;
  }
  return null;
}

/// Preference key. The language is not a secret; the existing injectable
/// [SecretStore] is reused so no extra storage dependency is needed.
const localeStorageKey = 'orangeone.locale';

/// The language the user selected, or null to follow the device language.
///
/// The choice is stored on the device and restored at startup. A storage
/// failure never blocks the app: the language then applies until restart.
final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
  name: 'localeControllerProvider',
);

class LocaleController extends Notifier<Locale?> {
  var _chosen = false;

  @override
  Locale? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(secretStoreProvider).read(localeStorageKey);
      final language = appLanguageFor(saved);
      // A selection made while reading wins over the stored value.
      if (ref.mounted && !_chosen && language != null) {
        state = language.locale;
      }
    } on Exception {
      // Keep following the device language.
    }
  }

  /// Applies [locale] immediately and remembers it for the next start.
  Future<void> select(Locale locale) async {
    final language = appLanguageFor(locale.languageCode);
    if (language == null) return;
    _chosen = true;
    state = language.locale;
    try {
      await ref
          .read(secretStoreProvider)
          .write(localeStorageKey, language.locale.languageCode);
    } on Exception {
      // The language stays applied for this run only.
    }
  }
}
