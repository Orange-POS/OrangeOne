import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// One tutorial as a vertical card: the thumbnail with the YouTube badge on
/// top, then the title, the full description and "Watch video". The height
/// follows the content, so long titles and descriptions are never cut. The
/// whole card opens the video.
class TutorialVideoCard extends StatelessWidget {
  const new({required this.video, required this.onWatch, super.key});

  final TutorialVideo video;
  final VoidCallback onWatch;

  /// The badge color of the supplied design (YouTube red).
  static const _youtubeRed = Color(0xFFFF0000);
  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final title = video.title.resolve(language);
    final description = video.description.resolve(language);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _radius,
        border: Border.all(color: OrangeTheme.actionDisabled),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: l10n.tutorialWatchSemantics(title),
          excludeSemantics: true,
          child: InkWell(
            onTap: onWatch,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    _Thumbnail(video.thumbnail),
                    Positioned(
                      top: 7,
                      right: 10,
                      child: _Badge(
                        label: l10n.tutorialYoutubeBadge,
                        color: _youtubeRed,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 20, 13, 9),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: const Key('tutorial-card-title'),
                        style: const TextStyle(
                          color: OrangeTheme.ink,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          key: const Key('tutorial-card-description'),
                          style: const TextStyle(
                            color: OrangeTheme.secondary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/icons/tutorial_play.svg',
                            width: 16,
                            height: 16,
                            colorFilter: const ColorFilter.mode(
                              OrangeTheme.action,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              l10n.tutorialWatchVideo,
                              style: const TextStyle(
                                color: OrangeTheme.action,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The preview across the full card width (2:1, as designed) inside a thin
/// outline; the outline alone shows while loading or without an image.
class _Thumbnail extends StatelessWidget {
  const new(this.url);
  final Uri url;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2,
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: _radius,
        border: Border.all(color: OrangeTheme.actionDisabled),
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: Image.network(
          url.toString(),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stack) => const SizedBox.expand(),
        ),
      ),
    ),
  );
}
