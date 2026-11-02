import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/app_version.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/features/settings/presentation/widgets/company_footer.dart';
import 'package:orange_one/features/settings/presentation/widgets/settings_row.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Settings in every flavor: application facts, the [demoSection] supplied by
/// app composition, help and about entries, and the Crashlytics verification
/// in the development flavor only.
class SettingsPage extends ConsumerWidget {
  const new({this.demoSection, super.key});

  /// The Demo Mode switch; composed by the app, not owned by this feature.
  final Widget? demoSection;

  static const _external = 'assets/icons/settings_external.svg';
  static const _headerHeight = 80.0;
  static const _panelRadius = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The crash tools exist in development only.
    final developerTools = ref.watch(crashTestControlsProvider);
    final l10n = context.l10n;
    final environment = developerTools ? ref.watch(environmentProvider) : null;
    final insets = MediaQuery.paddingOf(context);
    // The gradient spans the header and the corners of the panel below it,
    // so it runs from dark to light across the header as designed.
    final header =
        math.max(insets.top, OrangeTheme.topSafeArea) + _headerHeight;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: header + _panelRadius,
            child: const DecoratedBox(
              decoration: BoxDecoration(gradient: OrangeTheme.gradient),
            ),
          ),
          Column(
            children: [
              SafeArea(
                bottom: false,
                minimum: const EdgeInsets.only(top: OrangeTheme.topSafeArea),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('settings-back'),
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .2),
                          fixedSize: const Size(48, 48),
                        ),
                        icon: SvgPicture.asset(
                          'assets/icons/arrow_left.svg',
                          width: 24,
                          height: 24,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.goNamed('login'),
                      ),
                      Expanded(
                        child: Text(
                          l10n.settingsTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(_panelRadius),
                    ),
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      24 + insets.bottom,
                    ),
                    children: [
                      SettingsSectionHeading(l10n.settingsApplicationSection),
                      SettingsRow(
                        key: const Key('settings-app-version'),
                        height: 58,
                        icon: 'assets/icons/settings_info.svg',
                        label: l10n.settingsAppVersionLabel,
                        trailing: Text(
                          ref.watch(appVersionProvider),
                          style: const TextStyle(
                            color: OrangeTheme.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (demoSection != null) ...[
                        const _Separator(),
                        SettingsSectionHeading(
                          l10n.settingsDemonstrationSection,
                        ),
                        demoSection!,
                      ],
                      const _Separator(),
                      SettingsSectionHeading(l10n.settingsHelpSection),
                      // Design-only entries: their destinations are not defined
                      // yet, so they are deliberately not interactive.
                      SettingsRow(
                        key: const Key('settings-how-to-use'),
                        icon: 'assets/icons/settings_guide.svg',
                        label: l10n.settingsHowToUse,
                        trailing: settingsIcon(_external),
                      ),
                      const SizedBox(height: 14),
                      SettingsRow(
                        key: const Key('settings-privacy-policy'),
                        icon: 'assets/icons/settings_privacy.svg',
                        label: l10n.settingsPrivacyPolicy,
                        trailing: settingsIcon(_external),
                      ),
                      const SizedBox(height: 14),
                      SettingsRow(
                        key: const Key('settings-contact-support'),
                        icon: 'assets/icons/settings_mail.svg',
                        label: l10n.settingsContactSupport,
                        trailing: settingsIcon(_external),
                      ),
                      const SizedBox(height: 14),
                      SettingsSectionHeading(l10n.settingsAboutSection),
                      SettingsRow(
                        key: const Key('settings-about'),
                        icon: 'assets/icons/settings_device.svg',
                        label: l10n.settingsAbout,
                        trailing: settingsIcon(_external),
                      ),
                      if (developerTools) ...[
                        const _Separator(),
                        SettingsSectionHeading(l10n.settingsDeveloperSection),
                        Text(
                          '${l10n.settingsEnvironmentLabel}: '
                          '${environment?.name}',
                          key: const Key('settings-environment'),
                          style: const TextStyle(color: OrangeTheme.secondary),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const Key('trigger-crash-button'),
                          onPressed: () => _confirmCrash(context, ref),
                          child: Text(l10n.settingsCrashButton),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const Key('send-test-report-button'),
                          onPressed: () {
                            ref
                                .read(crashReporterProvider)
                                .recordTestNonFatal();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.settingsNonFatalSent),
                              ),
                            );
                          },
                          child: Text(l10n.settingsNonFatalButton),
                        ),
                      ],
                      const SizedBox(height: 28),
                      const CompanyFooter(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCrash(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsCrashConfirmTitle),
        content: Text(l10n.settingsCrashConfirmBody),
        actions: [
          TextButton(
            key: const Key('crash-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsCancel),
          ),
          FilledButton(
            key: const Key('crash-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsCrashConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      ref.read(crashReporterProvider).triggerTestCrash();
    }
  }
}

/// Thin rule between groups of Settings, as in the supplied design.
class _Separator extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 13, bottom: 14),
    child: Divider(height: 1, thickness: 1, color: OrangeTheme.actionDisabled),
  );
}
