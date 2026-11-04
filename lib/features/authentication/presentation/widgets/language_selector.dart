import 'package:flutter/material.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/language_menu.dart';

/// White pill showing a greeting in the current language; tapping it opens
/// the shared [LanguageMenu]. The choice applies immediately everywhere and
/// is remembered by `LocaleController`.
class LanguageSelector extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = currentAppLanguage(context);
    return LanguageMenu(
      key: const Key('language-selector'),
      tooltip: l10n.languageSelectorTooltip,
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
