import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDADCE0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('demo-mode-switch'),
              title: Text(l10n.demoModeTitle),
              subtitle: Text(
                available || active
                    ? l10n.demoModeDescription
                    : l10n.demoModeLocked,
              ),
              value: active,
              activeThumbColor: Colors.white,
              activeTrackColor: OrangeTheme.action,
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
          ),
        ),
      ],
    );
  }
}
