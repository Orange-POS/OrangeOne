import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/help_support/data/models/tutorial_video_model.dart';
import 'package:orange_one/features/help_support/data/repositories/firestore_tutorial_repository.dart';

void main() {
  const id = 'dQw4w9WgXcQ';
  Map<String, Object?> doc([Map<String, Object?> changes = const {}]) => {
    'title': 'How to Adjust Stock',
    'description': 'Learn how to manage product stock in OrangeOne.',
    'youtube_url': 'https://youtu.be/$id',
    'published': true,
    'order': 1,
    ...changes,
  };

  test('maps a complete published document', () {
    final video = tutorialFromDocument('stock', doc())!;
    expect(video.id, 'stock');
    expect(video.title.resolve('en'), 'How to Adjust Stock');
    expect(video.description.resolve('nl'), startsWith('Learn how'));
    expect(video.youtubeVideoId, id);
    expect(
      video.thumbnail.toString(),
      'https://i.ytimg.com/vi/$id/mqdefault.jpg',
    );
    expect(video.order, 1);
  });

  test('unpublished, untitled or non-YouTube documents are skipped', () {
    for (final changes in <Map<String, Object?>>[
      {'published': false},
      {'published': 'true'},
      {'published': null},
      {'title': null},
      {'title': '   '},
      {'title': 42},
      {'youtube_url': 'https://vimeo.com/123'},
      {'youtube_url': null},
    ]) {
      expect(
        tutorialFromDocument('x', doc(changes)),
        isNull,
        reason: '$changes',
      );
    }
  });

  test('titles and descriptions may be given per language', () {
    final video = tutorialFromDocument(
      'x',
      doc({
        'title': {'en': 'Login', 'nl': 'Inloggen', 'fr': 7},
        'description': {'en': 'Sign in with the POS QR code.'},
      }),
    )!;
    expect(video.title.resolve('nl'), 'Inloggen');
    expect(video.title.resolve('fr'), 'Login');
    expect(video.description.resolve('it'), 'Sign in with the POS QR code.');
  });

  test('a custom thumbnail must be https; otherwise YouTube preview', () {
    expect(
      tutorialFromDocument(
        'x',
        doc({'thumbnail_url': 'https://cdn.example.ch/a.jpg'}),
      )!.thumbnail.toString(),
      'https://cdn.example.ch/a.jpg',
    );
    for (final bad in ['http://cdn.example.ch/a.jpg', 'not a url', 5]) {
      expect(
        tutorialFromDocument('x', doc({'thumbnail_url': bad}))!.thumbnail.host,
        'i.ytimg.com',
        reason: '$bad',
      );
    }
  });

  test('the catalog keeps valid videos in order; ties keep their place', () {
    final catalog = catalogFrom([
      ('c', doc({'order': 3})),
      ('hidden', doc({'published': false, 'order': 0})),
      ('a', doc({'order': 1})),
      ('broken', doc({'youtube_url': 'nope'})),
      ('b1', doc({'order': 2})),
      ('b2', doc({'order': 2})),
      ('last', doc({'order': 'first please'})),
    ], fromCache: true);
    expect(catalog.videos.map((v) => v.id), ['a', 'b1', 'b2', 'c', 'last']);
    expect(catalog.fromCache, isTrue);
  });
}
