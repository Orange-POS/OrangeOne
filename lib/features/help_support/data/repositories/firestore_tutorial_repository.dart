import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orange_one/features/help_support/data/models/tutorial_video_model.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';
import 'package:orange_one/features/help_support/domain/repositories/tutorial_repository.dart';

/// Tutorials from Cloud Firestore of the build's own Firebase project.
///
/// Firestore keeps the last result on the device, so tutorials seen once stay
/// available offline. The query asks for published documents only, which is
/// also what the security rules allow (`firebase/firestore.rules`).
class FirestoreTutorialRepository implements TutorialRepository {
  const new(this._firestore);
  final FirebaseFirestore _firestore;

  @override
  Stream<TutorialCatalog> watchPublished() => _firestore
      .collection(TutorialFields.collection)
      .where(TutorialFields.published, isEqualTo: true)
      .orderBy(TutorialFields.order)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => catalogFrom([
          for (final doc in snapshot.docs) (doc.id, doc.data()),
        ], fromCache: snapshot.metadata.isFromCache),
      );
}

/// Valid published tutorials in display order; ties keep document order.
TutorialCatalog catalogFrom(
  List<(String, Map<String, Object?>)> documents, {
  bool fromCache = false,
}) {
  final videos = [
    for (final (id, data) in documents) ?tutorialFromDocument(id, data),
  ];
  final indexed = videos.indexed.toList()
    ..sort((a, b) {
      final byOrder = a.$2.order.compareTo(b.$2.order);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
  return TutorialCatalog([
    for (final (_, video) in indexed) video,
  ], fromCache: fromCache);
}

/// Used when the build has no Firebase configuration (local builds) or
/// Firebase failed to start: Help & Support says so instead of failing.
class UnavailableTutorialRepository implements TutorialRepository {
  const new();

  @override
  Stream<TutorialCatalog> watchPublished() =>
      Stream.error(const TutorialsUnavailable());
}

class TutorialsUnavailable implements Exception {
  const new();
}
