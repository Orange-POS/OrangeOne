import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// White, outlined card of one Settings row. Shared because Settings rows come
/// from more than one feature (the Demo Mode switch is composed by the app).
class SettingsCard extends StatelessWidget {
  const new({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: OrangeTheme.actionDisabled),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

/// Primary text of a Settings row.
const settingsLabelStyle = TextStyle(
  color: OrangeTheme.secondary,
  fontSize: 14,
  height: 1.25,
);

/// Darker text of a Settings row that holds a control (Demo Mode).
const settingsStrongLabelStyle = TextStyle(
  color: OrangeTheme.ink,
  fontSize: 14,
  height: 1.25,
  fontWeight: FontWeight.w500,
);
