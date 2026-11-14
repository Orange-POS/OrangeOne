import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/features/help_support/data/models/tutorial_video_model.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';
import 'package:orange_one/features/help_support/domain/repositories/tutorial_repository.dart';

/// One Firestore result: the documents (ID and fields) and whether it came
/// from the device cache because the server could not be reached.
typedef SupportVideoSnapshot = ({
  List<(String, Map<String, Object?>)> documents,
  bool fromCache,
});

/// The published support videos of the build's own Firebase project.
///
/// The query only asks for published documents (what the security rules
/// allow) and the app sorts by `sortOrder`, so a document without that
/// field is still delivered and reported instead of silently missing; no
/// composite index is needed. Firestore keeps the last result on the device
/// for offline use.
Stream<SupportVideoSnapshot> publishedSupportVideos(
  FirebaseFirestore firestore,
) => firestore
    .collection(TutorialFields.collection)
    .where(TutorialFields.published, isEqualTo: true)
    .snapshots(includeMetadataChanges: true)
    .map(
      (snapshot) => (
        documents: [for (final doc in snapshot.docs) (doc.id, doc.data())],
        fromCache: snapshot.metadata.isFromCache,
      ),
    );

/// Tutorials from Firestore ([publishedSupportVideos]).
///
/// Technical failures and data problems go to the app's [CrashReporter]
/// with the same classification and `OO-` references as API failures.
class FirestoreTutorialRepository implements TutorialRepository {
  const new(this._snapshots, this._reporter);
  final Stream<SupportVideoSnapshot> Function() _snapshots;
  final CrashReporter _reporter;

  /// Fixed operation label of every report (no document data).
  static const operation = 'FIRESTORE support_videos';

  @override
  Stream<TutorialCatalog> watchPublished() {
    // Data problems are reported once per screen visit, not per snapshot.
    final reported = <TutorialIssue, String?>{};
    return _snapshots()
        .map((snapshot) {
          final catalog = catalogFrom(
            snapshot.documents,
            fromCache: snapshot.fromCache,
          );
          for (final issue in catalog.issues.toSet()) {
            if (reported.containsKey(issue)) continue;
            reported[issue] = _reporter.recordFailure(
              AppFailure(
                FailureKind.protocol,
                'A support video document is incomplete.',
                code: issue.code,
              ),
              operation: operation,
            );
          }
          return catalog.withReference(
            catalog.issues.map((issue) => reported[issue]).nonNulls.firstOrNull,
          );
        })
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (error, stack, sink) =>
                sink.addError(_report(error, stack), stack),
          ),
        );
  }

  /// Classifies a Firestore error like an API failure and reports it through
  /// the existing policy (network/timeout throttled, setup and server faults
  /// always, cancellations and rate limits never).
  AppFailure _report(Object error, StackTrace stack) {
    final failure = tutorialFailureFrom(error);
    final reference = _reporter.recordFailure(
      failure,
      operation: operation,
      stack: stack,
    );
    return reference == null ? failure : failure.withReference(reference);
  }
}

/// A Firestore error as an [AppFailure]; the Firestore error code is kept as
/// the failure code, the message never contains server text.
AppFailure tutorialFailureFrom(Object error) {
  if (error is AppFailure) return error;
  final code = error is FirebaseException ? error.code : null;
  final kind = switch (code) {
    'unavailable' => FailureKind.network,
    'deadline-exceeded' => FailureKind.timeout,
    'cancelled' => FailureKind.cancelled,
    'resource-exhausted' => FailureKind.rateLimited,
    'permission-denied' ||
    'unauthenticated' ||
    'failed-precondition' ||
    'invalid-argument' ||
    'not-found' => FailureKind.configuration,
    _ => FailureKind.backend,
  };
  return AppFailure(
    kind,
    'The support videos could not be loaded.',
    code: code == null ? null : 'FIRESTORE_${code.toUpperCase()}',
  );
}

/// Shown published tutorials in `sortOrder` (ties keep document order) and
/// the problems of the published documents that were not usable as they are.
TutorialCatalog catalogFrom(
  List<(String, Map<String, Object?>)> documents, {
  bool fromCache = false,
}) {
  final mapped = [
    for (final (id, data) in documents) tutorialFromDocument(id, data),
  ];
  final indexed =
      [for (final document in mapped) ?document.video].indexed.toList()
        ..sort((a, b) {
          final byOrder = a.$2.order.compareTo(b.$2.order);
          return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
        });
  return TutorialCatalog(
    [for (final (_, video) in indexed) video],
    fromCache: fromCache,
    issues: [for (final document in mapped) ?document.issue],
  );
}

/// Used when the build has no Firebase configuration (local builds) or
/// Firebase failed to start: Help & Support says so instead of failing.
/// Not reported: without Firebase there is no Crashlytics either.
class UnavailableTutorialRepository implements TutorialRepository {
  const new();

  @override
  Stream<TutorialCatalog> watchPublished() =>
      Stream.error(const TutorialsUnavailable());
}

class TutorialsUnavailable implements Exception {
  const new();
}
