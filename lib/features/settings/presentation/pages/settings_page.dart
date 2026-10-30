import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Settings. For now it only holds the development-only Crashlytics
/// verification; the screen does not exist in staging or production builds.
class SettingsPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defense in depth: the route is not registered outside development.
    if (!ref.watch(crashTestControlsProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final environment = ref.watch(environmentProvider);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('settings-back'),
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('login'),
                    ),
                    Text(
                      l10n.settingsTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        l10n.settingsDeveloperSection,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.settingsEnvironmentLabel}: ${environment.name}',
                        key: const Key('settings-environment'),
                        style: const TextStyle(color: OrangeTheme.secondary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.settingsCrashHelper,
                        style: const TextStyle(color: OrangeTheme.secondary),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          key: const Key('trigger-crash-button'),
                          onPressed: () => _confirmCrash(context, ref),
                          child: Text(l10n.settingsCrashButton),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
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
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
