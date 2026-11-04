import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The app language currently shown, from the one app-wide selection.
AppLanguage currentAppLanguage(BuildContext context) =>
    appLanguageFor(Localizations.localeOf(context).languageCode) ??
    appLanguages.first;

/// Opens the menu of the six languages, listed by greeting, under [child].
/// Every screen that offers a language choice uses it, so they all change
/// the same [LocaleController] selection and always show the same language.
class LanguageMenu extends ConsumerWidget {
  const new({required this.tooltip, required this.child, super.key});

  final String tooltip;
  final Widget child;

  static const _menuColor = Color(0xFFF7F2FA);
  static const _divider = Color(0xFFCAC4D0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = currentAppLanguage(context);
    return PopupMenuButton<AppLanguage>(
      tooltip: tooltip,
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
      child: child,
    );
  }
}
