import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

void main() {
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
  testWidgets('gradient actions retain disabled state and tap behavior', (
    tester,
  ) async {
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
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final enabled = find.widgetWithText(FilledButton, 'Enabled');
    final disabled = find.widgetWithText(FilledButton, 'Disabled');
    Finder gradientInside(Finder button) => find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient ==
                OrangeTheme.gradient,
      ),
    );
    expect(gradientInside(enabled), findsOneWidget);
    expect(gradientInside(disabled), findsNothing);
    expect(
      tester
          .widget<Material>(
            find.descendant(of: disabled, matching: find.byType(Material)),
          )
          .color,
      const Color(0xFFDADCE0),
    );
    await tester.tap(enabled);
    await tester.tap(disabled);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
