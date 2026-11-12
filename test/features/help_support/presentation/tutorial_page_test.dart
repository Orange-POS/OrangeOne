import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/platform/external_launcher.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/features/help_support/data/repositories/firestore_tutorial_repository.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_catalog.dart';
import 'package:orange_one/features/help_support/domain/repositories/tutorial_repository.dart';
import 'package:orange_one/features/help_support/presentation/pages/tutorial_page.dart';
import 'package:orange_one/features/help_support/presentation/providers/help_support_providers.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/wifi_fakes.dart';

const _id = 'dQw4w9WgXcQ';

TutorialCatalog _catalog({bool fromCache = false, int count = 2}) =>
    catalogFrom(
      [
        (
          'stock',
          {
            'title': {'en': 'How to Adjust Stock', 'de': 'Bestand anpassen'},
            'description': 'Learn how to manage product stock in OrangeOne.',
            'youtubeVideoId': _id,
            'published': true,
            'sortOrder': 1,
          },
        ),
        (
          'login',
          {
            'title': 'How to Login',
            'youtubeVideoId': _id,
            'published': true,
            'sortOrder': 2,
          },
        ),
      ].take(count).toList(),
      fromCache: fromCache,
    );

class _Repository implements TutorialRepository {
  final controllers = <StreamController<TutorialCatalog>>[];

  StreamController<TutorialCatalog> get latest => controllers.last;

  @override
  Stream<TutorialCatalog> watchPublished() {
    final controller = StreamController<TutorialCatalog>();
    controllers.add(controller);
    return controller.stream;
  }
}

class _Launcher implements ExternalLauncher {
  final inApp = <Uri>[];
  final inBrowser = <Uri>[];
  bool appInstalled = true;
  bool browserWorks = true;

  @override
  Future<bool> openInApp(Uri uri) async {
    inApp.add(uri);
    return appInstalled;
  }

  @override
  Future<bool> openInBrowser(Uri uri) async {
    inBrowser.add(uri);
    return browserWorks;
  }
}

void main() {
  late _Repository repository;
  late _Launcher launcher;
  late ProviderContainer container;

  setUp(() {
    repository = _Repository();
    launcher = _Launcher();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    TutorialRepository? source,
  }) async {
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        utcNowProvider.overrideWithValue(() => testNow),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        wifiConnected,
        qrCameraBuilderProvider.overrideWithValue(
          (context, onCode, onStatus) => const SizedBox(),
        ),
        tutorialRepositoryProvider.overrideWithValue(source ?? repository),
        externalLauncherProvider.overrideWithValue(launcher),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTutorial(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('settings-tutorial'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> showVideos(WidgetTester tester, TutorialCatalog catalog) async {
    repository.latest.add(catalog);
    await tester.pumpAndSettle();
  }

  testWidgets('the renamed Settings row opens the Tutorial screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-tutorial')),
      200,
    );
    expect(find.text('OrangeOne Tutorial'), findsOneWidget);
    expect(find.text('How to Use OrangeOne'), findsNothing);

    await tester.tap(find.byKey(const Key('settings-tutorial')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TutorialPage), findsOneWidget);
    expect(find.text('Tutorial'), findsOneWidget);
    expect(find.text('YouTube Guides'), findsOneWidget);
    expect(find.byType(Skeleton), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorial-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tutorial')), findsOneWidget);
    // Leaving the screen stops listening to Firestore.
    expect(repository.latest.hasListener, isFalse);
  });

  testWidgets('published videos are listed with their details', (tester) async {
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(tester, _catalog());
    expect(find.text('How to Adjust Stock'), findsOneWidget);
    expect(
      find.text('Learn how to manage product stock in OrangeOne.'),
      findsOneWidget,
    );
    expect(find.text('How to Login'), findsOneWidget);
    expect(find.text('YouTube video'), findsNWidgets(2));
    expect(find.text('Watch video'), findsNWidgets(2));

    // A remote change (a video removed) updates the open screen.
    await showVideos(tester, _catalog(count: 1));
    expect(find.text('How to Login'), findsNothing);
  });

  testWidgets('cards keep a readable width on tablets', (tester) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(tester, _catalog());
    final card = tester.getRect(find.byKey(const Key('tutorial-stock')));
    expect(card.width, 560);
    expect(card.center.dx, closeTo(512, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('titles follow the selected app language', (tester) async {
    await pumpApp(tester);
    await container
        .read(localeControllerProvider.notifier)
        .select(const Locale('de'));
    await tester.pumpAndSettle();
    await openTutorial(tester);
    await showVideos(tester, _catalog());
    expect(find.text('Bestand anpassen'), findsOneWidget);
    // Untranslated titles fall back to English.
    expect(find.text('How to Login'), findsOneWidget);
    expect(find.text('YouTube-Anleitungen'), findsOneWidget);
  });

  testWidgets('Watch video opens the YouTube app with the canonical link', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(tester, _catalog());
    await tester.tap(find.text('Watch video').first);
    await tester.pumpAndSettle();
    expect(
      launcher.inApp.single.toString(),
      'https://www.youtube.com/watch?v=$_id',
    );
    expect(launcher.inBrowser, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('without the YouTube app the browser is only offered', (
    tester,
  ) async {
    launcher.appInstalled = false;
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(tester, _catalog());
    await tester.tap(find.text('Watch video').first);
    await tester.pumpAndSettle();
    expect(find.text('The YouTube app is not installed.'), findsOneWidget);
    expect(launcher.inBrowser, isEmpty);

    launcher.browserWorks = false;
    await tester.tap(find.byKey(const Key('tutorial-open-in-browser')));
    await tester.pumpAndSettle();
    expect(launcher.inBrowser.single.host, 'www.youtube.com');
    expect(find.text('The video could not be opened.'), findsOneWidget);
  });

  testWidgets('no published videos, offline and errors are explained', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(tester, _catalog(count: 0));
    expect(find.text('No tutorials are available yet.'), findsOneWidget);
    expect(find.byKey(const Key('tutorial-retry')), findsNothing);

    await showVideos(tester, _catalog(count: 0, fromCache: true));
    expect(
      find.text('Connect to the internet to load the tutorials.'),
      findsOneWidget,
    );

    repository.latest.addError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(find.text('The tutorials could not be loaded.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tutorial-retry')));
    await tester.pump();
    expect(repository.controllers, hasLength(2));
    await showVideos(tester, _catalog());
    expect(find.text('How to Adjust Stock'), findsOneWidget);
  });

  testWidgets('the getting-started document of the console is shown', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(
      tester,
      catalogFrom([
        (
          'getting-started-001',
          {
            'title': 'Getting started',
            'description': 'Your first steps with OrangeOne.',
            'category': 'basics',
            'language': 'en',
            'published': true,
            'sortOrder': 1,
            'youtubeVideoId': _id,
            'thumbnailUrl': 'https://cdn.example.ch/getting-started.jpg',
          },
        ),
      ]),
    );
    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Your first steps with OrangeOne.'), findsOneWidget);
    expect(find.text('No tutorials are available yet.'), findsNothing);
  });

  testWidgets('videos of another language are left out', (tester) async {
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(
      tester,
      catalogFrom([
        (
          'en',
          {
            'title': 'English video',
            'language': 'en',
            'published': true,
            'sortOrder': 1,
            'youtubeVideoId': _id,
          },
        ),
        (
          'de',
          {
            'title': 'Deutsches Video',
            'language': 'de',
            'published': true,
            'sortOrder': 2,
            'youtubeVideoId': _id,
          },
        ),
      ]),
    );
    expect(find.text('English video'), findsOneWidget);
    expect(find.text('Deutsches Video'), findsNothing);
  });

  testWidgets('unusable published documents are an error, not "empty"', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTutorial(tester);
    await showVideos(
      tester,
      catalogFrom([
        (
          'getting-started-001',
          {'title': 'Broken', 'published': true, 'sortOrder': 1},
        ),
      ]).withReference('OO-ABC123'),
    );
    expect(find.text('No tutorials are available yet.'), findsNothing);
    expect(
      find.text('The tutorials could not be loaded. (Ref: OO-ABC123)'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tutorial-retry')), findsOneWidget);
  });

  testWidgets('a reported Firestore failure shows its reference', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTutorial(tester);
    repository.latest.addError(
      const AppFailure(
        FailureKind.configuration,
        'The support videos could not be loaded.',
      ).withReference('OO-XYZ789'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The tutorials could not be loaded. (Ref: OO-XYZ789)'),
      findsOneWidget,
    );
  });

  testWidgets('without Firebase the screen reports unavailable tutorials', (
    tester,
  ) async {
    await pumpApp(tester, source: const UnavailableTutorialRepository());
    await openTutorial(tester);
    await tester.pumpAndSettle();
    expect(find.text('The tutorials could not be loaded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
