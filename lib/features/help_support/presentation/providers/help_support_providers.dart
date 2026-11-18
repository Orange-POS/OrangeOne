import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/platform/external_launcher.dart';
import 'package:orange_one/features/help_support/data/repositories/firestore_tutorial_repository.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';
import 'package:orange_one/features/help_support/domain/repositories/tutorial_repository.dart';

/// Firestore of the build's Firebase project (Development for DEV and STG,
/// Production for PROD), or an unavailable source without Firebase.
final tutorialRepositoryProvider = Provider<TutorialRepository>(
  (ref) => Firebase.apps.isEmpty
      ? const UnavailableTutorialRepository()
      : FirestoreTutorialRepository(
          () => publishedSupportVideos(FirebaseFirestore.instance),
          ref.watch(crashReporterProvider),
        ),
  name: 'tutorialRepositoryProvider',
);

/// Live tutorial list while the Tutorial screen is open.
final StreamProvider<TutorialCatalog> tutorialCatalogProvider =
    StreamProvider.autoDispose<TutorialCatalog>(
      (ref) => ref.watch(tutorialRepositoryProvider).watchPublished(),
      name: 'tutorialCatalogProvider',
      // Failures stay visible until the user taps Try again.
      retry: (retryCount, error) => null,
    );

/// How a "Watch video" request ended.
enum WatchOutcome { openedInApp, appMissing }

final tutorialVideoOpenerProvider = Provider<TutorialVideoOpener>(
  (ref) => TutorialVideoOpener(ref.watch(externalLauncherProvider)),
  name: 'tutorialVideoOpenerProvider',
);

/// Opens tutorials in the YouTube app, never inside OrangeOne. The browser is
/// used only when the user explicitly asks for it after the app was missing.
class TutorialVideoOpener {
  const new(this._launcher);
  final ExternalLauncher _launcher;

  Future<WatchOutcome> watch(TutorialVideo video) async =>
      await _launcher.openInApp(video.watchUrl)
      ? WatchOutcome.openedInApp
      : WatchOutcome.appMissing;

  Future<bool> watchInBrowser(TutorialVideo video) =>
      _launcher.openInBrowser(video.watchUrl);
}
