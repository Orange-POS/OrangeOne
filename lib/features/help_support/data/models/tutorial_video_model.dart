import 'package:orange_one/features/help_support/domain/entities/localized_text.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';

/// Firestore document fields of a tutorial (collection `support_videos`).
abstract final class TutorialFields {
  static const collection = 'support_videos';
  static const title = 'title';
  static const description = 'description';
  static const youtubeUrl = 'youtube_url';
  static const thumbnailUrl = 'thumbnail_url';
  static const published = 'published';
  static const order = 'order';
}

/// Maps one document to a [TutorialVideo], or null when it is unpublished or
/// incomplete. Managed data is untrusted: a bad document is skipped and
/// never breaks the list.
TutorialVideo? tutorialFromDocument(String id, Map<String, Object?> data) {
  if (data[TutorialFields.published] != true) return null;
  final title = _text(data[TutorialFields.title]);
  final videoId = TutorialVideo.videoIdFrom(
    _string(data[TutorialFields.youtubeUrl]),
  );
  if (title == null || title.isEmpty || videoId == null) return null;
  final order = data[TutorialFields.order];
  return TutorialVideo(
    id: id,
    title: title,
    description:
        _text(data[TutorialFields.description]) ?? const LocalizedText({}),
    youtubeVideoId: videoId,
    thumbnail:
        _https(_string(data[TutorialFields.thumbnailUrl])) ??
        TutorialVideo.defaultThumbnail(videoId),
    order: order is num && order.isFinite ? order : double.maxFinite,
  );
}

String? _string(Object? value) => value is String ? value : null;

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
