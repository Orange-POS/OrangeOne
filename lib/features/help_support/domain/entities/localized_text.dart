/// Text managed outside the app, either one value for every language or one
/// value per language code (`en`, `de`, `fr`, `it`, `tr`, `ta`).
class LocalizedText {
  const new(this.values);

  /// The same text in every language.
  new single(String text) : values = {fallbackLanguage: text};

  /// Language code → text; never empty for a valid tutorial title.
  final Map<String, String> values;

  static const fallbackLanguage = 'en';

  bool get isEmpty => values.values.every((text) => text.trim().isEmpty);

  /// The text for [languageCode], else English, else any provided text.
  String resolve(String languageCode) {
    for (final code in [languageCode, fallbackLanguage]) {
      final text = values[code]?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    for (final text in values.values) {
      if (text.trim().isNotEmpty) return text.trim();
    }
    return '';
  }
}
