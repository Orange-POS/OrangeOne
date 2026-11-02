import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/settings_card.dart';

/// The Demo Mode switch for Settings. It is always off after a restart and
/// only an explicit tap turns it on.
class DemoModeSection extends ConsumerWidget {
  const new({
    required this.available,
    required this.onEnabled,
    required this.onDisabled,
    super.key,
  });

  /// False while a real session exists or is being restored: the two never
  /// run side by side.
  final bool available;

  /// Called after Demo Mode started (to show the sample QR login).
  final VoidCallback onEnabled;

  /// Called after Demo Mode ended and its data was discarded.
  final VoidCallback onDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final active = ref.watch(demoModeProvider) != null;
    return SettingsCard(
      child: SwitchListTile(
        key: const Key('demo-mode-switch'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(l10n.demoModeTitle, style: settingsStrongLabelStyle),
        // Only the reason it cannot change is worth a second line.
        subtitle: available || active
            ? null
            : Text(
                l10n.demoModeLocked,
                style: const TextStyle(color: OrangeTheme.secondary),
              ),
        value: active,
        activeThumbColor: Colors.white,
        activeTrackColor: OrangeTheme.brand,
        onChanged: available || active
            ? (value) {
                final controller = ref.read(demoModeProvider.notifier);
                if (value) {
                  controller.enable();
                  onEnabled();
                } else {
                  controller.disable();
                  onDisabled();
                }
              }
            : null,
      ),
    );
  }
}
