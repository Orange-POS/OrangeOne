import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('one accessibility node with the label, blocks hidden', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Skeleton(
          label: 'Loading product details',
          child: Column(children: [SkeletonInfoRow(), SkeletonForm()]),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading product details'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(Skeleton)),
      matchesSemantics(label: 'Loading product details', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('the shimmer moves, and stands still with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const Skeleton(label: 'Loading', child: SkeletonLines())),
    );
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(
      _host(
        const Skeleton(label: 'Loading', child: SkeletonLines()),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('blocks use the neutral colors, translucent white on dark', (
    tester,
  ) async {
    Color colorOf(WidgetTester tester) {
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(SkeletonBox),
          matching: find.byType(Container),
        ),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    await tester.pumpWidget(
      _host(const Skeleton(label: 'Loading', child: SkeletonBox())),
    );
    expect(colorOf(tester), OrangeTheme.skeletonBase);
    await tester.pumpWidget(
      _host(
        const Skeleton(label: 'Loading', onDark: true, child: SkeletonBox()),
      ),
    );
    expect(colorOf(tester), OrangeTheme.skeletonOnDarkBase);
  });

  testWidgets('without a label it adds no announcement', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            Text('Looking up product…'),
            Skeleton(label: null, child: SkeletonLines()),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Looking up product…'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Loading')), findsNothing);
    semantics.dispose();
  });

  testWidgets('presets lay out on a small phone without overflow', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Skeleton(
            label: 'Loading',
            child: Column(
              children: [
                SkeletonInfoRow(),
                SkeletonTiles(),
                SkeletonListTile(),
                SkeletonCard(),
                SkeletonForm(fields: 4),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
