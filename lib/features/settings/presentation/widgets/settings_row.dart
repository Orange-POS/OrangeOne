import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/settings_card.dart';

/// One Settings row: an orange outline icon, a label and an optional
/// trailing value or icon. Rows without [onTap] are not interactive.
class SettingsRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.height = 56,
    this.verticalPadding = 12,
    super.key,
  });

  /// Asset path of a 24-point outline icon.
  final String icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;

  /// Rows whose trailing control is a 48-point touch target use less padding
  /// so they keep the designed height.
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: verticalPadding,
        ),
        child: Row(
          children: [
            settingsIcon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: settingsLabelStyle)),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
    return SettingsCard(
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// A 24-point outline icon in the action color.
Widget settingsIcon(String asset) => SvgPicture.asset(
  asset,
  width: 24,
  height: 24,
  colorFilter: const ColorFilter.mode(OrangeTheme.action, BlendMode.srcIn),
);

/// Capitalized section heading of the Settings list.
class SettingsSectionHeading extends StatelessWidget {
  const new(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          color: OrangeTheme.ink,
          fontSize: 14,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}
