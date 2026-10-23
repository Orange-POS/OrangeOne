import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

import '../../support/product_details_fakes.dart';

void main() {
  testWidgets('header and card share one continuous gradient', (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(
            FakeDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, padding: EdgeInsets.only(top: 34)),
            child: RepaintBoundary(
              key: Key('gradient-preview'),
              child: ProductDetailsPage(barcode: '0010101010'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('gradient-preview')),
    );
    await tester.runAsync(() async {
      final actual = await boundary.toImage();
      final recorder = ui.PictureRecorder();
      final bounds = Offset.zero & size;
      Canvas(recorder).drawRect(
        bounds,
        Paint()..shader = OrangeTheme.gradient.createShader(bounds),
      );
      final picture = recorder.endRecording();
      final expected = await picture.toImage(390, 844);
      final actualBytes = (await actual.toByteData())!;
      final expectedBytes = (await expected.toByteData())!;
      // Sample unoccupied navigation and card-padding pixels. Independent
      // card/header shaders or colored card fills break this visual contract.
      for (final point in [const Offset(200, 20), const Offset(24, 124)]) {
        final offset = (point.dy.toInt() * 390 + point.dx.toInt()) * 4;
        for (var channel = 0; channel < 4; channel++) {
          expect(
            actualBytes.getUint8(offset + channel),
            closeTo(expectedBytes.getUint8(offset + channel), 1),
            reason: 'Gradient discontinuity at $point, channel $channel',
          );
        }
      }
      actual.dispose();
      expected.dispose();
      picture.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('details fits $size with enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productDetailsRepositoryProvider.overrideWithValue(
              FakeDetailsRepository(),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const ProductDetailsPage(barcode: '0010101010'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final headerPosition = tester.getTopLeft(find.text('Product'));
      expect(find.text('Update Price'), findsNothing);
      expect(find.text('Update Stock'), findsNothing);
      final stock = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.tooltip == 'Add stock (coming soon)',
      );
      expect(tester.widget<IconButton>(stock).onPressed, isNull);
      expect(find.byKey(const Key('product-hero-barcode')), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Update price'));
      expect(find.byTooltip('Update price').hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.text('Product')), headerPosition);
      expect(find.byTooltip('Back to scanner').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
