import 'package:orange_one/features/help_support/domain/entities/localized_text.dart';

/// A published YouTube tutorial shown in Help & Support.
///
/// Only a validated YouTube video ID is kept, so the app opens nothing but
/// `https://www.youtube.com/watch?v=<id>`, whatever the managed data says.
class TutorialVideo {
  const new({
    required this.id,
    required this.title,
    required this.description,
    required this.youtubeVideoId,
    required this.thumbnail,
    required this.order,
    this.category,
    this.language,
  });

  final String id;
  final LocalizedText title;
  final LocalizedText description;
  final String youtubeVideoId;
  final Uri thumbnail;

  /// Display position (`sortOrder`); lower comes first.
  final num order;

  /// Grouping for a future support library; not shown yet.
  final String? category;

  /// Primary language code of the video (`en`, `de`, …); null when the video
  /// suits every language.
  final String? language;

  /// The canonical page the YouTube app opens.
  Uri get watchUrl =>
      Uri.https('www.youtube.com', '/watch', {'v': youtubeVideoId});

  /// YouTube's own 16:9 preview image of the video.
  static Uri defaultThumbnail(String videoId) =>
      Uri.https('i.ytimg.com', '/vi/$videoId/mqdefault.jpg');

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
  };

  /// The video ID in a plain ID or a YouTube link (`watch?v=`, `youtu.be/`,
  /// `shorts/`, `embed/`, `live/`), or null for anything else.
  static String? videoIdFrom(String? value) {
    final text = value?.trim() ?? '';
    if (_videoId.hasMatch(text)) return text;
    final uri = Uri.tryParse(text);
    if (uri == null || !const {'https', 'http'}.contains(uri.scheme)) {
      return null;
    }
    // Path segments and query parameters are decoded on access, which throws
    // for malformed percent-encoded UTF-8 (`%FF`): such a link is no video.
    try {
      final id = _idFrom(uri);
      return id != null && _videoId.hasMatch(id) ? id : null;
    } on FormatException {
      return null;
    }
  }

  static String? _idFrom(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.host == 'youtu.be' && segments.length == 1) {
      return segments.single;
    }
    if (!_hosts.contains(uri.host)) return null;
    if (segments.length == 1 && segments.single == 'watch') {
      return uri.queryParameters['v'];
    }
    if (segments.length == 2 &&
        const {'shorts', 'embed', 'live'}.contains(segments.first)) {
      return segments.last;
    }
    return null;
  }
}
