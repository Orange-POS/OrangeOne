import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';

import '../support/auth_fakes.dart';

void main() {
  Future<FakeAuthRepository> start(
    WidgetTester tester,
    Future<BackendFeatures> Function() meta,
  ) async {
    final repository = FakeAuthRepository()..restored = testSession;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          utcNowProvider.overrideWithValue(() => testNow),
          backendFeaturesProvider.overrideWith((ref) => meta()),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('a compatible shop opens Home as before', (tester) async {
    await start(tester, () async => BackendFeatures.baseline);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(find.byKey(const Key('compatibility-title')), findsNothing);
  });

  testWidgets('an app below the shop minimum shows the update screen; '
      'sign-out still works', (tester) async {
    final repository = await start(
      tester,
      () async => BackendFeatures.refused(BackendRefusal.appUpgradeRequired),
    );
    expect(find.text('Update required'), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsNothing);

    await tester.tap(find.byKey(const Key('compatibility-sign-out')));
    await tester.pumpAndSettle();
    expect(repository.signOuts, 1);
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maintenance clears after Try again once the shop answers', (
    tester,
  ) async {
    var maintenance = true;
    await start(
      tester,
      () async => maintenance
          ? BackendFeatures.refused(BackendRefusal.maintenance)
          : BackendFeatures(
              BackendFeatures.baseline.names,
              apiVersion: '1.0.0',
              confirmed: true,
            ),
    );
    expect(find.text('Under maintenance'), findsOneWidget);

    maintenance = false;
    await tester.tap(find.byKey(const Key('compatibility-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server with an older contract is not supported', (
    tester,
  ) async {
    await start(
      tester,
      () async => const BackendFeatures(
        {'stock_adjustments'},
        apiVersion: '0.9.0',
        confirmed: true,
      ),
    );
    expect(find.text('Server not supported'), findsOneWidget);
  });
}
