import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/bootstrap.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';

import '../support/auth_fakes.dart';

void main() {
  for (final environment in AppEnvironment.values) {
    for (final debug in [true, false]) {
      testWidgets('${environment.name} debug=$debug diagnostics access', (
        tester,
      ) async {
        final settings = ApplicationSettings.parse(
          environment,
          {},
          debugBuild: debug,
        );
        final container = ProviderContainer.test(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            developmentDiagnosticsProvider.overrideWithValue(
              settings.diagnosticsEnabled,
            ),
          ],
        );
        final router = container.read(routerProvider);
        final paths = router.configuration.routes.whereType<GoRoute>().map(
          (route) => route.path,
        );
        expect(
          paths.contains('/diagnostics/initialization'),
          debug && environment == AppEnvironment.development,
        );
        router.go('/diagnostics/initialization');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        if (!settings.diagnosticsEnabled) {
          expect(find.text('Page not found'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
    'startup configuration failure shows only a safe recovery message',
    (tester) async {
      await tester.pumpWidget(const ConfigurationErrorApp());
      expect(
        find.text(
          'Application configuration is invalid. Contact your administrator.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    },
  );
}
