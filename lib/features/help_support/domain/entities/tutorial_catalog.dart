import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';

/// The published tutorials in display order.
class TutorialCatalog {
  const new(this.videos, {this.fromCache = false});

  final List<TutorialVideo> videos;

  /// True when the list comes from the device copy because the server could
  /// not be reached; an empty cached list means "not loaded yet".
  final bool fromCache;
}
