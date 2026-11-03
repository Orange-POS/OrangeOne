import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/monitoring/reportable_failure.dart';
import 'package:orange_one/features/help_support/data/repositories/firestore_tutorial_repository.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';

/// Records what the app would send to Crashlytics; applies the real policy.
class _Reporter implements CrashReporter {
  final failures = <(AppFailure, String)>[];
  var _next = 0;

  @override
  String? recordFailure(
    AppFailure failure, {
    required String operation,
    StackTrace? stack,
  }) {
    if (reportPolicyFor(failure.kind) == ReportPolicy.never) return null;
    failures.add((failure, operation));
    return 'OO-TEST${++_next}';
  }

  @override
  void recordFatal(Object error, StackTrace stack) {}

  @override
  void recordTestNonFatal() {}

  @override
  void setIdentity(CrashIdentity? identity) {}

  @override
  void triggerTestCrash() {}
}

const _id = 'dQw4w9WgXcQ';

Map<String, Object?> _doc([Map<String, Object?> changes = const {}]) => {
  'title': 'Getting started',
  'description': 'Learn how to manage product stock in OrangeOne.',
  'category': 'basics',
  'language': 'en',
  'published': true,
  'sortOrder': 1,
  'youtubeVideoId': _id,
  'thumbnailUrl': 'https://cdn.example.ch/a.jpg',
  ...changes,
};

void main() {
  late StreamController<SupportVideoSnapshot> snapshots;
  late _Reporter reporter;
  late FirestoreTutorialRepository repository;

  void prepare() {
    snapshots = StreamController();
    reporter = _Reporter();
    repository = FirestoreTutorialRepository(() => snapshots.stream, reporter);
  }

  setUp(prepare);

  SupportVideoSnapshot snapshot(
    List<(String, Map<String, Object?>)> docs, {
    bool fromCache = false,
  }) => (documents: docs, fromCache: fromCache);

  test('sorts the published documents by sortOrder', () async {
    final catalogs = <TutorialCatalog>[];
    final subscription = repository.watchPublished().listen(catalogs.add);
    snapshots.add(
      snapshot([
        ('second', _doc({'sortOrder': 2})),
        ('getting-started-001', _doc()),
      ]),
    );
    await pumpEventQueue();
    expect(catalogs.single.videos.map((v) => v.id), [
      'getting-started-001',
      'second',
    ]);
    expect(reporter.failures, isEmpty);
    await subscription.cancel();
  });

  test('a genuinely empty collection is not reported', () async {
    final catalogs = <TutorialCatalog>[];
    final subscription = repository.watchPublished().listen(catalogs.add);
    snapshots
      ..add(snapshot([]))
      ..add(snapshot([], fromCache: true));
    await pumpEventQueue();
    expect(catalogs.map((c) => c.videos), [isEmpty, isEmpty]);
    expect(catalogs.last.fromCache, isTrue);
    expect(reporter.failures, isEmpty);
    await subscription.cancel();
  });

  test(
    'a data problem is reported once per visit with its reference',
    () async {
      final catalogs = <TutorialCatalog>[];
      final subscription = repository.watchPublished().listen(catalogs.add);
      final broken = snapshot([
        ('getting-started-001', _doc({'youtubeVideoId': 'not a video'})),
      ]);
      snapshots
        ..add(broken)
        ..add(broken);
      await pumpEventQueue();
      expect(reporter.failures, hasLength(1));
      final (failure, operation) = reporter.failures.single;
      expect(failure.kind, FailureKind.protocol);
      expect(failure.code, 'INVALID_VIDEO_ID');
      expect(operation, 'FIRESTORE support_videos');
      // No document data reaches monitoring.
      expect(failure.message, isNot(contains('getting-started')));
      expect(catalogs.map((c) => c.errorReference), ['OO-TEST1', 'OO-TEST1']);
      expect(catalogs.last.hasUnusableDocuments, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'Firestore errors are classified and reported like API errors',
    () async {
      for (final (code, kind, reported) in [
        ('permission-denied', FailureKind.configuration, true),
        ('failed-precondition', FailureKind.configuration, true),
        ('unavailable', FailureKind.network, true),
        ('deadline-exceeded', FailureKind.timeout, true),
        ('internal', FailureKind.backend, true),
        ('cancelled', FailureKind.cancelled, false),
        ('resource-exhausted', FailureKind.rateLimited, false),
      ]) {
        prepare();
        Object? error;
        final subscription = repository.watchPublished().listen(
          (_) {},
          onError: (Object e) => error = e,
        );
        snapshots.addError(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
        await pumpEventQueue();
        final failure = error! as AppFailure;
        expect(failure.kind, kind, reason: code);
        expect(failure.code, 'FIRESTORE_${code.toUpperCase()}', reason: code);
        expect(reporter.failures, hasLength(reported ? 1 : 0), reason: code);
        expect(
          failure.errorReference,
          reported ? 'OO-TEST1' : isNull,
          reason: code,
        );
        await subscription.cancel();
      }
    },
  );

  test('unexpected non-Firestore errors are reported as backend faults', () {
    expect(tutorialFailureFrom(StateError('x')).kind, FailureKind.backend);
    expect(tutorialFailureFrom(StateError('x')).code, isNull);
  });
}
