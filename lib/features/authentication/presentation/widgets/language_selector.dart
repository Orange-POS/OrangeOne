import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// White pill showing a greeting in the current language; tapping it opens a
/// menu of the six supported languages. The choice applies immediately and
/// is remembered by [LocaleController].
class LanguageSelector extends ConsumerWidget {
  const new({super.key});

  static const _menuColor = Color(0xFFF7F2FA);
  static const _divider = Color(0xFFCAC4D0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current =
        appLanguageFor(Localizations.localeOf(context).languageCode) ??
        appLanguages.first;
    return PopupMenuButton<AppLanguage>(
      key: const Key('language-selector'),
      tooltip: l10n.languageSelectorTooltip,
      color: _menuColor,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(minWidth: 168),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      position: PopupMenuPosition.under,
      onSelected: (language) =>
          ref.read(localeControllerProvider.notifier).select(language.locale),
      itemBuilder: (context) => [
        for (final (index, language) in appLanguages.indexed)
          PopupMenuItem<AppLanguage>(
            key: Key('language-${language.locale.languageCode}'),
            value: language,
            padding: EdgeInsets.zero,
            child: Semantics(
              selected: language == current,
              child: Container(
                width: double.infinity,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: index == appLanguages.length - 1
                        ? null
                        : const Border(bottom: BorderSide(color: _divider)),
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Text(
                        language.greeting,
                        semanticsLabel: language.name,
                        style: const TextStyle(
                          color: OrangeTheme.action,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      // The visible pill is 40 high; the padding keeps a 48 touch target.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Semantics(
          label: l10n.languageSelectorSemantics(current.name),
          excludeSemantics: true,
          // Intrinsic width keeps the pill at its 150 minimum instead of
          // stretching to the whole row.
          child: IntrinsicWidth(
            child: Container(
              height: 40,
              constraints: const BoxConstraints(minWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Text(
                current.greeting,
                style: const TextStyle(
                  color: OrangeTheme.action,
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
