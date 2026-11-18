import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/environment_loader.dart';
import 'package:orange_one/features/initialization/presentation/pages/initialization_page.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

void main() {
  testWidgets('renders pending configuration then the injected environment', (
    tester,
  ) async {
    final pending = Completer<AppEnvironment>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentLoaderProvider.overrideWithValue(() => pending.future),
        ],
        child: const MaterialApp(home: InitializationPage()),
      ),
    );

    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.textContaining('Application initialized'), findsNothing);
    pending.complete(AppEnvironment.staging);
    await tester.pumpAndSettle();

    expect(find.byType(Skeleton), findsNothing);
    expect(find.textContaining('Environment: staging'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a safe error and retries through the injected loader', (
    tester,
  ) async {
    final recovery = Completer<AppEnvironment>();
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentLoaderProvider.overrideWithValue(() async {
            calls++;
            if (calls == 1) throw StateError('private diagnostic details');
            return await recovery.future;
          }),
        ],
        child: const MaterialApp(home: InitializationPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to initialize the application. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private diagnostic details'), findsNothing);
    expect(calls, 1);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    recovery.complete(AppEnvironment.production);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.textContaining('Environment: production'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
