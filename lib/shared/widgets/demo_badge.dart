import 'package:flutter/material.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Whether the app runs on Demo Mode sample data. Set once by app
/// composition, so screens can mark their title without depending on the
/// demo feature.
class DemoScope extends InheritedWidget {
  const new({required this.active, required super.child, super.key});
  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoScope>()?.active ?? false;

  @override
  bool updateShouldNotify(DemoScope oldWidget) => active != oldWidget.active;
}

/// [title] followed by a small Demo badge while Demo Mode runs; just the
/// title otherwise. It never adds height to the navigation bar.
class TitleWithDemoBadge extends StatelessWidget {
  const new({required this.title, super.key});
  final Widget title;

  @override
  Widget build(BuildContext context) {
    if (!DemoScope.of(context)) return title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: title),
        const SizedBox(width: 8),
        const DemoBadge(),
      ],
    );
  }
}

/// Compact white pill reading "Demo" on the orange navigation bar.
class DemoBadge extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      key: const Key('demo-badge'),
      label: l10n.demoModeTitle,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Text(
          l10n.demoBadge,
          maxLines: 1,
          style: const TextStyle(
            color: OrangeTheme.dark,
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
