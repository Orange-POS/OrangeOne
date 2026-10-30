import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/l10n/l10n.dart';

import '../support/auth_fakes.dart';

class _SpyReporter implements CrashReporter {
  int crashes = 0;
  int nonFatals = 0;

  @override
  void triggerTestCrash() => crashes++;

  @override
  void recordTestNonFatal() => nonFatals++;

  @override
  void recordFatal(Object error, StackTrace stack) {}

  @override
  String? recordFailure(
    AppFailure failure, {
    required String operation,
    StackTrace? stack,
  }) => null;

  @override
  void setIdentity(CrashIdentity? identity) {}
}

ProviderContainer _container(
  AppEnvironment environment,
  _SpyReporter reporter, {
  bool debug = false,
}) {
  final settings = ApplicationSettings.parse(
    environment,
    {},
    debugBuild: debug,
  );
  return ProviderContainer.test(
    overrides: [
      environmentProvider.overrideWithValue(environment),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      crashTestControlsProvider.overrideWithValue(settings.crashTestEnabled),
      crashReporterProvider.overrideWithValue(reporter),
    ],
  );
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  final router = container.read(routerProvider)..go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('only the development flavor enables the crash test controls', () {
    for (final environment in AppEnvironment.values) {
      for (final debug in [true, false]) {
        expect(
          ApplicationSettings.parse(
            environment,
            {},
            debugBuild: debug,
          ).crashTestEnabled,
          environment == AppEnvironment.development,
          reason: '${environment.name} debug=$debug',
        );
      }
    }
    // Closed unless the bootstrap enables it.
    expect(ProviderContainer.test().read(crashTestControlsProvider), isFalse);
  });

  for (final environment in AppEnvironment.values) {
    final development = environment == AppEnvironment.development;
    testWidgets(
      '${environment.name}: settings route and gear exist=$development',
      (tester) async {
        final container = _container(environment, _SpyReporter());
        final paths = container
            .read(routerProvider)
            .configuration
            .routes
            .whereType<GoRoute>()
            .map((route) => route.path);
        expect(paths.contains('/settings'), development);

        await _mount(tester, container, '/login');
        expect(
          find.byKey(const Key('settings-button')),
          development ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const Key('scan-login-button')), findsOneWidget);

        await _mount(tester, container, '/settings');
        expect(
          find.byKey(const Key('trigger-crash-button')),
          development ? findsOneWidget : findsNothing,
        );
        if (!development) expect(find.text('Page not found'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('the gear opens Settings; the crash needs a confirmation', (
    tester,
  ) async {
    final reporter = _SpyReporter();
    final container = _container(AppEnvironment.development, reporter);
    await _mount(tester, container, '/login');

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-environment')), findsOneWidget);
    expect(find.text('Environment: development'), findsOneWidget);

    await tester.tap(find.byKey(const Key('trigger-crash-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crash-cancel')));
    await tester.pumpAndSettle();
    expect(reporter.crashes, 0);

    await tester.tap(find.byKey(const Key('trigger-crash-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crash-confirm')));
    await tester.pumpAndSettle();
    expect(reporter.crashes, 1);

    await tester.tap(find.byKey(const Key('send-test-report-button')));
    await tester.pump();
    expect(reporter.nonFatals, 1);
    expect(reporter.crashes, 1);

    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-login-button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
