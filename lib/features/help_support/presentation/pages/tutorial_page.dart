import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';
import 'package:orange_one/features/help_support/presentation/providers/help_support_providers.dart';
import 'package:orange_one/features/help_support/presentation/widgets/tutorial_video_card.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/panel_scaffold.dart';

/// Help & Support tutorials: the published YouTube guides, managed remotely.
class TutorialPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final catalog = ref.watch(tutorialCatalogProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return PanelScaffold(
      title: l10n.tutorialTitle,
      backButtonKey: const Key('tutorial-back'),
      onBack: () =>
          context.canPop() ? context.pop() : context.goNamed('settings'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottom),
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.tutorialYoutubeGuides,
              style: const TextStyle(
                color: OrangeTheme.ink,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...catalog.when(
            // A refresh keeps the list on screen.
            skipLoadingOnReload: true,
            loading: () => [
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: CircularProgressIndicator(color: OrangeTheme.action),
                ),
              ),
            ],
            error: (error, stack) => [
              _Message(
                key: const Key('tutorial-error'),
                text: _withReference(
                  l10n.tutorialError,
                  error is AppFailure ? error.errorReference : null,
                ),
                onRetry: () => ref.invalidate(tutorialCatalogProvider),
              ),
            ],
            data: (catalog) {
              final videos = catalog.forLanguage(
                Localizations.localeOf(context).languageCode,
              );
              if (videos.isNotEmpty) {
                return [
                  for (final video in videos) ...[
                    TutorialVideoCard(
                      key: Key('tutorial-${video.id}'),
                      video: video,
                      onWatch: () => _watch(context, ref, video),
                    ),
                    const SizedBox(height: 15),
                  ],
                ];
              }
              // Published documents exist but none can be shown: a data
              // problem (already reported), never "no tutorials".
              if (catalog.hasUnusableDocuments) {
                return [
                  _Message(
                    key: const Key('tutorial-error'),
                    text: _withReference(
                      l10n.tutorialError,
                      catalog.errorReference,
                    ),
                    onRetry: () => ref.invalidate(tutorialCatalogProvider),
                  ),
                ];
              }
              return [
                _Message(
                  key: const Key('tutorial-empty'),
                  text: catalog.fromCache
                      ? l10n.tutorialOffline
                      : l10n.tutorialEmpty,
                  onRetry: catalog.fromCache
                      ? () => ref.invalidate(tutorialCatalogProvider)
                      : null,
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  /// The message with the `OO-` reference of a reported failure, written
  /// like the app's other reported errors.
  static String _withReference(String text, String? reference) =>
      reference == null ? text : '$text (Ref: $reference)';

  /// Opens the YouTube app. When it is missing, the browser is offered and
  /// used only if the user chooses it.
  Future<void> _watch(
    BuildContext context,
    WidgetRef ref,
    TutorialVideo video,
  ) async {
    final opener = ref.read(tutorialVideoOpenerProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (await opener.watch(video) == WatchOutcome.openedInApp) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.tutorialYoutubeMissing),
          action: SnackBarAction(
            key: const Key('tutorial-open-in-browser'),
            label: l10n.tutorialOpenInBrowser,
            onPressed: () async {
              if (await opener.watchInBrowser(video)) return;
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.tutorialOpenFailed)),
              );
            },
          ),
        ),
      );
  }
}

class _Message extends StatelessWidget {
  const new({required this.text, this.onRetry, super.key});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: OrangeTheme.secondary, fontSize: 14),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('tutorial-retry'),
            onPressed: onRetry,
            child: Text(context.l10n.tutorialRetry),
          ),
        ],
      ],
    ),
  );
}
