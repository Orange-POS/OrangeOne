import 'package:orange_one/features/help_support/domain/entities/localized_text.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';

/// The existing Firestore schema of a support video (collection
/// `support_videos`). The app follows it; it never renames fields.
abstract final class TutorialFields {
  static const collection = 'support_videos';
  static const title = 'title';
  static const description = 'description';
  static const category = 'category';
  static const language = 'language';
  static const published = 'published';
  static const sortOrder = 'sortOrder';
  static const youtubeVideoId = 'youtubeVideoId';
  static const thumbnailUrl = 'thumbnailUrl';
}

/// One mapped document: the video to show (if any) and what is wrong with
/// the document (if anything). Managed data is untrusted.
typedef TutorialDocument = ({TutorialVideo? video, TutorialIssue? issue});

/// Maps one document. Unpublished documents are neither shown nor a problem.
/// A published document without a title or a usable YouTube video is not
/// shown and reported as an issue; one without `sortOrder` is shown last and
/// reported, so a data mistake never makes a video silently disappear.
TutorialDocument tutorialFromDocument(String id, Map<String, Object?> data) {
  if (data[TutorialFields.published] != true) return (video: null, issue: null);
  final title = _text(data[TutorialFields.title]);
  if (title == null || title.isEmpty) {
    return (video: null, issue: TutorialIssue.missingTitle);
  }
  final videoId = TutorialVideo.videoIdFrom(
    _string(data[TutorialFields.youtubeVideoId]),
  );
  if (videoId == null) {
    return (video: null, issue: TutorialIssue.invalidVideoId);
  }
  final order = data[TutorialFields.sortOrder];
  final hasOrder = order is num && order.isFinite;
  return (
    video: TutorialVideo(
      id: id,
      title: title,
      description:
          _text(data[TutorialFields.description]) ?? const LocalizedText({}),
      youtubeVideoId: videoId,
      thumbnail:
          _https(_string(data[TutorialFields.thumbnailUrl])) ??
          TutorialVideo.defaultThumbnail(videoId),
      order: hasOrder ? order : double.maxFinite,
      category: _token(data[TutorialFields.category]),
      language: _language(data[TutorialFields.language]),
    ),
    issue: hasOrder ? null : TutorialIssue.missingSortOrder,
  );
}

String? _string(Object? value) => value is String ? value : null;

String? _token(Object? value) {
  final text = _string(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

/// The primary language subtag in lower case (`en-US` → `en`).
String? _language(Object? value) =>
    _token(value)?.toLowerCase().split(RegExp('[-_]')).first;

/// A plain string, or a map of language code to string.
LocalizedText? _text(Object? value) {
  if (value is String) return LocalizedText.single(value);
  if (value is Map) {
    return LocalizedText({
      for (final MapEntry(:key, :value) in value.entries)
        if (key is String && value is String) key: value,
    });
  }
  return null;
}

Uri? _https(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
