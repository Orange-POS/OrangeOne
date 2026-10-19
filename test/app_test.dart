import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';

import 'support/auth_fakes.dart';

void main() {
  testWidgets('resume keeps the session without another server validation', (
    tester,
  ) async {
    final repository = FakeAuthRepository()..restored = testSession;
    final container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        utcNowProvider.overrideWithValue(() => testNow),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Logout'), findsOneWidget);
    expect(repository.restores, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.restores, 1);
    expect(container.read(sessionControllerProvider).value, testSession);
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(repository.signOuts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles the device zero-size first frame before normal layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(Size.zero);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const App(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown routes show a fallback and return to login', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        environmentProvider.overrideWithValue(AppEnvironment.development),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();

    final router = container.read(routerProvider)..go('/unknown');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    await tester.tap(find.text('Return to OrangeONE'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final environment in AppEnvironment.values) {
    testWidgets('initializes ${environment.name} through the router', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentProvider.overrideWithValue(environment),
            developmentDiagnosticsProvider.overrideWithValue(
              environment == AppEnvironment.development,
            ),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(App));
      ProviderScope.containerOf(context)
          .read(routerProvider)
          .go('/diagnostics/initialization');
      await tester.pumpAndSettle();
      if (environment == AppEnvironment.development) {
        expect(find.text('OrangeONE'), findsOneWidget);
        expect(
          find.text(
            'Application initialized\nEnvironment: ${environment.name}',
          ),
          findsOneWidget,
        );
      } else {
        expect(find.text('Page not found'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'protects home, scanner push/pop results and authenticated redirect',
    (tester) async {
      final repository = FakeAuthRepository();
      final container = ProviderContainer.test(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          utcNowProvider.overrideWithValue(() => testNow),
          qrCameraBuilderProvider.overrideWithValue(
            (context, onCode, onStatus) => FilledButton(
              onPressed: () => onCode('fixture QR'),
              child: const Text('Simulate QR scan'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider)..go('/home');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(find.text('Tap to scan Barcode'), findsNothing);
      final result = router.pushNamed<bool>('qrLogin');
      await tester.pumpAndSettle();
      expect(find.text('Scan QR Code'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to login'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      await tester.tap(find.byKey(const Key('scan-login-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simulate QR scan'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('Tap to scan Barcode'), findsOneWidget);
      router.go('/login/scan');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      expect(find.text('Tap to scan QR'), findsOneWidget);
      expect(repository.signIns, 1);
      expect(repository.signOuts, 1);
      router.go('/login?reason=expired');
      await tester.pumpAndSettle();
      expect(
        find.text('Your session expired. Scan a new POS QR code.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('login adapts to $size without overflow', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tap to scan QR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
