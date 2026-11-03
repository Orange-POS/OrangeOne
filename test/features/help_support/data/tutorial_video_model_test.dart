import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/help_support/data/models/tutorial_video_model.dart';
import 'package:orange_one/features/help_support/data/repositories/firestore_tutorial_repository.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';

const _id = 'dQw4w9WgXcQ';

/// A document exactly as it exists in Firestore (`support_videos`).
Map<String, Object?> doc([Map<String, Object?> changes = const {}]) => {
  'title': 'Getting started',
  'description': 'Learn how to manage product stock in OrangeOne.',
  'category': 'basics',
  'language': 'en',
  'published': true,
  'sortOrder': 1,
  'youtubeVideoId': _id,
  'thumbnailUrl': 'https://cdn.example.ch/getting-started.jpg',
  ...changes,
};

void main() {
  test('the app reads the existing Firestore schema', () {
    expect(TutorialFields.collection, 'support_videos');
    expect(
      [
        TutorialFields.title,
        TutorialFields.description,
        TutorialFields.category,
        TutorialFields.language,
        TutorialFields.published,
        TutorialFields.sortOrder,
        TutorialFields.youtubeVideoId,
        TutorialFields.thumbnailUrl,
      ],
      [
        'title',
        'description',
        'category',
        'language',
        'published',
        'sortOrder',
        'youtubeVideoId',
        'thumbnailUrl',
      ],
    );
  });

  test('the rules cover the collection; no composite index is needed', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    expect(rules, contains('match /support_videos/{video}'));
    expect(rules, contains('resource.data.published == true'));
    final indexes = jsonDecode(
      File('firebase/firestore.indexes.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(indexes['indexes'], isEmpty);
  });

  test(
    'the query filters on published only and never orders on the server',
    () {
      // A server-side orderBy drops every document without that field; this
      // hid the published getting-started video once.
      final source = File(
        'lib/features/help_support/data/repositories/'
        'firestore_tutorial_repository.dart',
      ).readAsStringSync();
      expect(source, contains('isEqualTo: true'));
      expect(source, isNot(contains('.orderBy(')));
    },
  );

  test('maps the published getting-started document completely', () {
    final mapped = tutorialFromDocument('getting-started-001', doc());
    expect(mapped.issue, isNull);
    final video = mapped.video!;
    expect(video.id, 'getting-started-001');
    expect(video.title.resolve('en'), 'Getting started');
    expect(video.description.resolve('en'), startsWith('Learn how'));
    expect(video.youtubeVideoId, _id);
    expect(
      video.thumbnail.toString(),
      'https://cdn.example.ch/getting-started.jpg',
    );
    expect(video.order, 1);
    expect(video.category, 'basics');
    expect(video.language, 'en');
  });

  test('a YouTube link in youtubeVideoId is accepted as well', () {
    expect(
      tutorialFromDocument(
        'x',
        doc({'youtubeVideoId': 'https://youtu.be/$_id'}),
      ).video?.youtubeVideoId,
      _id,
    );
  });

  test('optional fields fall back safely', () {
    final video = tutorialFromDocument(
      'x',
      doc({
        'description': null,
        'category': ' ',
        'language': 'EN-us',
        'thumbnailUrl': 'http://insecure.example.ch/a.jpg',
      }),
    ).video!;
    expect(video.description.resolve('en'), isEmpty);
    expect(video.category, isNull);
    expect(video.language, 'en');
    expect(video.thumbnail.host, 'i.ytimg.com');
  });

  test('unpublished documents are neither shown nor a problem', () {
    for (final published in [false, 'true', null]) {
      final mapped = tutorialFromDocument('x', doc({'published': published}));
      expect(mapped.video, isNull);
      expect(mapped.issue, isNull);
    }
  });

  test('unusable published documents are reported, never silently lost', () {
    for (final (changes, issue) in [
      (<String, Object?>{'title': null}, TutorialIssue.missingTitle),
      ({'title': '  '}, TutorialIssue.missingTitle),
      ({'youtubeVideoId': null}, TutorialIssue.invalidVideoId),
      ({'youtubeVideoId': 'https://vimeo.com/1'}, TutorialIssue.invalidVideoId),
    ]) {
      final mapped = tutorialFromDocument('x', doc(changes));
      expect(mapped.video, isNull, reason: '$changes');
      expect(mapped.issue, issue, reason: '$changes');
    }
  });

  test('a missing sortOrder still shows the video, last, and is reported', () {
    final mapped = tutorialFromDocument('x', doc({'sortOrder': null}));
    expect(mapped.video, isNotNull);
    expect(mapped.issue, TutorialIssue.missingSortOrder);
  });

  test('the catalog is sorted by sortOrder; ties keep their place', () {
    final catalog = catalogFrom([
      ('c', doc({'sortOrder': 3})),
      ('a', doc({'sortOrder': 1})),
      ('broken', doc({'youtubeVideoId': 'nope'})),
      ('b1', doc({'sortOrder': 2})),
      ('b2', doc({'sortOrder': 2})),
      ('unordered', doc({'sortOrder': 'first please'})),
    ], fromCache: true);
    expect(catalog.videos.map((v) => v.id), [
      'a',
      'b1',
      'b2',
      'c',
      'unordered',
    ]);
    expect(catalog.issues, [
      TutorialIssue.invalidVideoId,
      TutorialIssue.missingSortOrder,
    ]);
    expect(catalog.hasUnusableDocuments, isTrue);
    expect(catalog.fromCache, isTrue);
  });

  group('language', () {
    TutorialCatalog catalog(List<String?> languages) => catalogFrom([
      for (final (i, language) in languages.indexed)
        ('v$i', doc({'language': language, 'sortOrder': i})),
    ]);
    List<String> ids(TutorialCatalog c, String code) => [
      for (final v in c.forLanguage(code)) v.id,
    ];

    test('videos in the app language plus videos for every language', () {
      expect(ids(catalog(['en', 'nl', null]), 'nl'), ['v1', 'v2']);
    });

    test('without videos in that language, English ones are shown', () {
      expect(ids(catalog(['en', 'nl', null]), 'ta'), ['v0', 'v2']);
    });

    test('a language never hides every video', () {
      expect(ids(catalog(['fr', 'it']), 'tr'), ['v0', 'v1']);
      expect(ids(catalog([null]), 'tr'), ['v0']);
    });
  });
}
