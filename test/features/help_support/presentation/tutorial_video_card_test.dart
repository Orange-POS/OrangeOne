import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/help_support/domain/entities/localized_text.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';
import 'package:orange_one/features/help_support/presentation/widgets/tutorial_video_card.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

const _longDescription =
    'Learn how to count the products on your shelves, enter the counted '
    'quantity, add new deliveries or remove damaged items, check the live '
    'preview before saving, confirm the change and see the updated stock '
    'on the product details screen of OrangeOne.';

TutorialVideo _video({String description = 'Short text.', String? title}) =>
    TutorialVideo(
      id: 'stock',
      title: LocalizedText.single(title ?? 'How to Adjust Stock'),
      description: LocalizedText.single(description),
      youtubeVideoId: 'dQw4w9WgXcQ',
      thumbnail: Uri.parse('https://cdn.example.invalid/a.jpg'),
      order: 1,
    );

void main() {
  var taps = 0;

  Future<void> pump(
    WidgetTester tester,
    TutorialVideo video, {
    double width = 390,
    double textScale = 1,
  }) async {
    taps = 0;
    tester.view.physicalSize = Size(width, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 2000),
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          theme: OrangeTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TutorialVideoCard(video: video, onWatch: () => taps++),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderParagraph paragraph(WidgetTester tester, String key) =>
      tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(RichText),
        ),
      );

  test('the long description has 30 words or more', () {
    expect(_longDescription.split(' ').length, greaterThanOrEqualTo(30));
  });

  testWidgets('thumbnail and badge on top, then title, text and action', (
    tester,
  ) async {
    await pump(tester, _video());
    final thumbnail = tester.getRect(find.byType(AspectRatio));
    final badge = tester.getRect(find.text('YouTube video'));
    final title = tester.getRect(find.text('How to Adjust Stock'));
    final description = tester.getRect(find.text('Short text.'));
    final watch = tester.getRect(find.text('Watch video'));
    // The thumbnail spans the card at 2:1 and carries the badge top right.
    expect(thumbnail.width / thumbnail.height, closeTo(2, .01));
    expect(thumbnail.contains(badge.center), isTrue);
    expect(badge.right, greaterThan(thumbnail.center.dx));
    expect(title.top, greaterThan(thumbnail.bottom));
    expect(description.top, greaterThan(title.bottom));
    expect(watch.top, greaterThan(description.bottom));
  });

  for (final (width, scale) in [(320.0, 1.0), (390.0, 1.0), (390.0, 2.0)]) {
    testWidgets('a 30+ word description is fully visible at $width pt, '
        'text x$scale', (tester) async {
      await pump(
        tester,
        _video(description: _longDescription),
        width: width,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      final text = paragraph(tester, 'tutorial-card-description');
      expect(text.maxLines, isNull);
      expect(text.didExceedMaxLines, isFalse);
      expect(find.text(_longDescription), findsOneWidget);
      // The whole description lies inside the card, above the action.
      final card = tester.getRect(find.byType(TutorialVideoCard));
      final description = tester.getRect(
        find.byKey(const Key('tutorial-card-description')),
      );
      expect(card.contains(description.bottomRight), isTrue);
      expect(
        tester.getRect(find.text('Watch video')).top,
        greaterThan(description.bottom),
      );
    });
  }

  testWidgets('the card grows with its content', (tester) async {
    await pump(tester, _video());
    final short = tester.getSize(find.byType(TutorialVideoCard)).height;
    await pump(
      tester,
      _video(
        description: _longDescription,
        title: 'How to adjust, add and remove stock for products at the POS',
      ),
    );
    final long = tester.getSize(find.byType(TutorialVideoCard)).height;
    expect(long, greaterThan(short + 40));
    expect(paragraph(tester, 'tutorial-card-title').didExceedMaxLines, isFalse);
  });

  testWidgets('a missing description leaves no gap or placeholder', (
    tester,
  ) async {
    await pump(tester, _video(description: ''));
    expect(find.byKey(const Key('tutorial-card-description')), findsNothing);
    expect(find.text('Watch video'), findsOneWidget);
  });

  testWidgets('the whole card opens the video', (tester) async {
    await pump(tester, _video());
    await tester.tap(find.byType(AspectRatio));
    await tester.tap(find.text('Watch video'));
    expect(taps, 2);
  });
}
