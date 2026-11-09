import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/presentation/providers/startup_configuration_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/settings_card.dart';

/// Settings section to choose and save the sign-in workflow the app starts
/// with. Workflows this build cannot run are listed but cannot be chosen.
class StartupWorkflowSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref
        .watch(startupConfigurationControllerProvider)
        .effectiveWorkflow;
    return SettingsCard(
      child: Column(
        children: [
          for (final workflow in StartupWorkflow.values)
            ListTile(
              key: Key('startup-workflow-${workflow.storageValue}'),
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              enabled: workflow.available,
              selected: workflow == selected,
              selectedColor: OrangeTheme.ink,
              title: Text(_title(l10n, workflow), style: settingsLabelStyle),
              subtitle: Text(
                workflow.available
                    ? _description(l10n, workflow)
                    : l10n.startupWorkflowUnavailable,
                style: const TextStyle(color: OrangeTheme.secondary),
              ),
              trailing: workflow == selected
                  ? const Icon(Icons.check, color: OrangeTheme.action)
                  : null,
              onTap: () => unawaited(
                ref
                    .read(startupConfigurationControllerProvider.notifier)
                    .select(workflow),
              ),
            ),
        ],
      ),
    );
  }

  static String _title(AppLocalizations l10n, StartupWorkflow workflow) =>
      switch (workflow) {
        StartupWorkflow.qrLogin => l10n.startupWorkflowQr,
        StartupWorkflow.credentialsLogin => l10n.startupWorkflowCredentials,
      };

  static String _description(AppLocalizations l10n, StartupWorkflow workflow) =>
      switch (workflow) {
        StartupWorkflow.qrLogin => l10n.startupWorkflowQrDescription,
        StartupWorkflow.credentialsLogin =>
          l10n.startupWorkflowCredentialsDescription,
      };
}
