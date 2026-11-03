import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';

/// What is wrong with a published support video document. The [code] is
/// the stable value reported to monitoring.
enum TutorialIssue {
  missingTitle('MISSING_TITLE'),
  invalidVideoId('INVALID_VIDEO_ID'),
  missingSortOrder('MISSING_SORT_ORDER');

  new(this.code);
  final String code;
}

/// The published tutorials in display order.
class TutorialCatalog {
  const new(
    this.videos, {
    this.fromCache = false,
    this.issues = const [],
    this.errorReference,
  });

  final List<TutorialVideo> videos;

  /// True when the list comes from the device copy because the server could
  /// not be reached; an empty cached list means "not loaded yet".
  final bool fromCache;

  /// One entry per published document with a data problem.
  final List<TutorialIssue> issues;

  /// The monitoring reference of the reported data problem, if any.
  final String? errorReference;

  /// Published documents that cannot be shown at all.
  bool get hasUnusableDocuments =>
      issues.any((issue) => issue != TutorialIssue.missingSortOrder);

  TutorialCatalog withReference(String? reference) => TutorialCatalog(
    videos,
    fromCache: fromCache,
    issues: issues,
    errorReference: reference,
  );

  /// The videos for [languageCode]: videos in that language plus videos for
  /// every language; without any in that language, the English ones; and
  /// without English ones, all videos. A language never hides everything.
  List<TutorialVideo> forLanguage(String languageCode) {
    bool fits(TutorialVideo video, String code) =>
        video.language == null || video.language == code;
    for (final code in [languageCode, 'en']) {
      if (videos.any((video) => video.language == code)) {
        return [
          for (final video in videos)
            if (fits(video, code)) video,
        ];
      }
    }
    final universal = [
      for (final video in videos)
        if (video.language == null) video,
    ];
    return universal.isNotEmpty ? universal : videos;
  }
}
