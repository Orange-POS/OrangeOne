import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

void main() {
  test('supplied button colors cover normal, pressed and disabled states', () {
    final theme = OrangeTheme.light;
    final filled = theme.filledButtonTheme.style!;
    final outlined = theme.outlinedButtonTheme.style!;
    expect(OrangeTheme.action, const Color(0xFFF56600));
    expect(OrangeTheme.actionPressed, const Color(0xFFC84E00));
    for (final states in [
      <WidgetState>{},
      {WidgetState.pressed},
      {WidgetState.disabled},
    ]) {
      final disabled = states.contains(WidgetState.disabled);
      final color = disabled
          ? OrangeTheme.actionDisabled
          : states.contains(WidgetState.pressed)
          ? OrangeTheme.actionPressed
          : OrangeTheme.action;
      expect(filled.backgroundColor!.resolve(states), color);
      expect(
        filled.foregroundColor!.resolve(states),
        disabled ? OrangeTheme.actionDisabledLabel : Colors.white,
      );
      expect(outlined.backgroundColor!.resolve(states), Colors.white);
      expect(outlined.side!.resolve(states)!.color, color);
      expect(
        outlined.foregroundColor!.resolve(states),
        disabled ? OrangeTheme.actionDisabledLabel : color,
      );
    }
    expect(filled.backgroundBuilder, isNull);
    expect(filled.foregroundBuilder, isNull);
    expect(OrangeTheme.gradient.colors, [
      const Color(0xFFBE4602),
      const Color(0xFFFF8A33),
    ]);
  });
  test('native launch backgrounds share the exported brand artwork', () {
    final source = File('assets/branding/launch_gradient.png')
        .readAsBytesSync();
    for (final path in [
      'android/app/src/main/res/drawable-nodpi/brand_launch_background.png',
      'ios/Runner/Assets.xcassets/LaunchBackground.imageset/launch_gradient.png',
    ]) {
      expect(File(path).readAsBytesSync(), orderedEquals(source), reason: path);
    }
  });
  testWidgets(
    'primary and outlined buttons inherit colors and preserve disabled taps',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: OrangeTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(
                  onPressed: () => calls++,
                  child: const Text('Enabled'),
                ),
                const FilledButton(onPressed: null, child: Text('Disabled')),
                const OutlinedButton(
                  onPressed: null,
                  child: Text('Outlined disabled'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Color? fill(Finder button) => tester
          .widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)),
          )
          .color;
      expect(
        fill(find.widgetWithText(FilledButton, 'Enabled')),
        OrangeTheme.action,
      );
      expect(
        fill(find.widgetWithText(FilledButton, 'Disabled')),
        OrangeTheme.actionDisabled,
      );
      expect(fill(find.byType(OutlinedButton)), Colors.white);
      expect(
        DefaultTextStyle.of(tester.element(find.text('Enabled'))).style.shadows,
        isNull,
      );
      await tester.tap(find.text('Enabled'));
      await tester.tap(find.text('Disabled'));
      await tester.tap(find.text('Outlined disabled'));
      expect(calls, 1);
    },
  );
}
