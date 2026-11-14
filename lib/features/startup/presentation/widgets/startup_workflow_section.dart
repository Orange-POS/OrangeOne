import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/session/session_lifecycle.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/presentation/providers/startup_configuration_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/settings_card.dart';

/// Settings section to choose and save the sign-in method the app starts
/// with. Methods this build cannot run are listed but cannot be chosen, and
/// nothing can be changed while a session exists (sign out first).
class StartupWorkflowSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref
        .watch(startupConfigurationControllerProvider)
        .effectiveMethod;
    final signedOut = ref.watch(sessionLifecycleProvider).signedOut;
    return SettingsCard(
      child: Column(
        children: [
          for (final workflow in AuthenticationMethod.values)
            ListTile(
              key: Key('startup-workflow-${workflow.storageValue}'),
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              enabled: workflow.available && signedOut,
              selected: workflow == selected,
              selectedColor: OrangeTheme.ink,
              title: Text(_title(l10n, workflow), style: settingsLabelStyle),
              subtitle: Text(
                !workflow.available
                    ? l10n.startupWorkflowUnavailable
                    : signedOut
                    ? _description(l10n, workflow)
                    : l10n.startupWorkflowSignOutFirst,
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

  static String _title(AppLocalizations l10n, AuthenticationMethod workflow) =>
      switch (workflow) {
        AuthenticationMethod.qrLogin => l10n.startupWorkflowQr,
        AuthenticationMethod.oidc => l10n.startupWorkflowOidc,
        AuthenticationMethod.credentials => l10n.startupWorkflowCredentials,
      };

  static String _description(
    AppLocalizations l10n,
    AuthenticationMethod workflow,
  ) => switch (workflow) {
    AuthenticationMethod.qrLogin => l10n.startupWorkflowQrDescription,
    AuthenticationMethod.oidc => l10n.startupWorkflowOidcDescription,
    AuthenticationMethod.credentials =>
      l10n.startupWorkflowCredentialsDescription,
  };
}
