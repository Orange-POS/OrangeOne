import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/startup/data/repositories/stored_startup_configuration_repository.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/domain/repositories/startup_configuration_repository.dart';
import 'package:orange_one/features/startup/presentation/providers/startup_configuration_providers.dart';
import 'package:orange_one/features/startup/presentation/widgets/startup_workflow_section.dart';
import 'package:orange_one/l10n/l10n.dart';

import '../../support/auth_fakes.dart';

/// A store that never answers, like a stalled keychain.
class _StalledRepository implements StartupConfigurationRepository {
  @override
  Future<StartupConfiguration> load() =>
      Completer<StartupConfiguration>().future;

  @override
  Future<void> save(StartupConfiguration configuration) async {}
}

void main() {
  group('bootstrap load', () {
    test(
      'nothing saved, an unknown value or a read failure: QR login',
      () async {
        final store = MemorySecretStore();
        final repository = StoredStartupConfigurationRepository(store);
        expect(
          (await loadStartupConfiguration(repository)).workflow,
          StartupWorkflow.qrLogin,
        );
        store.values[startupWorkflowStorageKey] = 'smart_card';
        expect(
          (await loadStartupConfiguration(repository)).workflow,
          StartupWorkflow.qrLogin,
        );
        store.failure = storageFailure;
        expect(
          (await loadStartupConfiguration(repository)).workflow,
          StartupWorkflow.qrLogin,
        );
      },
    );

    test('a saved workflow is restored at the next start', () async {
      final store = MemorySecretStore()
        ..values[startupWorkflowStorageKey] = 'qr_login';
      final loaded = await loadStartupConfiguration(
        StoredStartupConfigurationRepository(store),
      );
      expect(loaded.workflow, StartupWorkflow.qrLogin);
    });

    testWidgets('a stalled store never blocks the start', (tester) async {
      final loading = loadStartupConfiguration(_StalledRepository());
      await tester.pump(startupConfigurationLoadLimit);
      expect((await loading).workflow, StartupWorkflow.qrLogin);
    });

    test('a saved but unavailable workflow runs the fallback', () {
      const saved = StartupConfiguration(
        workflow: StartupWorkflow.credentialsLogin,
      );
      expect(saved.effectiveWorkflow, StartupWorkflow.qrLogin);
    });

    test('the controller starts from the bootstrap configuration', () {
      const saved = StartupConfiguration(
        workflow: StartupWorkflow.credentialsLogin,
      );
      final container = ProviderContainer.test(
        overrides: [savedStartupConfigurationProvider.overrideWithValue(saved)],
      );
      expect(
        container.read(startupConfigurationControllerProvider).workflow,
        StartupWorkflow.credentialsLogin,
      );
    });
  });

  group('selection', () {
    test('an available workflow is selected and saved', () async {
      final store = MemorySecretStore();
      final container = ProviderContainer.test(
        overrides: [secretStoreProvider.overrideWithValue(store)],
      );
      final controller = container.read(
        startupConfigurationControllerProvider.notifier,
      );
      expect(await controller.select(StartupWorkflow.qrLogin), isTrue);
      expect(store.values[startupWorkflowStorageKey], 'qr_login');
      expect(
        container.read(startupConfigurationControllerProvider).workflow,
        StartupWorkflow.qrLogin,
      );
    });

    test('an unavailable workflow is refused and nothing is saved', () async {
      final store = MemorySecretStore();
      final container = ProviderContainer.test(
        overrides: [secretStoreProvider.overrideWithValue(store)],
      );
      final controller = container.read(
        startupConfigurationControllerProvider.notifier,
      );
      expect(
        await controller.select(StartupWorkflow.credentialsLogin),
        isFalse,
      );
      expect(store.writes, 0);
      expect(
        container.read(startupConfigurationControllerProvider).workflow,
        StartupWorkflow.qrLogin,
      );
    });

    test('a save failure keeps the selection for this run', () async {
      final store = MemorySecretStore()..failure = storageFailure;
      final container = ProviderContainer.test(
        overrides: [secretStoreProvider.overrideWithValue(store)],
      );
      expect(
        await container
            .read(startupConfigurationControllerProvider.notifier)
            .select(StartupWorkflow.qrLogin),
        isTrue,
      );
      expect(
        container.read(startupConfigurationControllerProvider).workflow,
        StartupWorkflow.qrLogin,
      );
    });
  });

  testWidgets('the section lists the workflows; unavailable ones cannot be '
      'chosen', (tester) async {
    final store = MemorySecretStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secretStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StartupWorkflowSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QR code'), findsOneWidget);
    expect(find.text('Username and password'), findsOneWidget);
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    final credentials = tester.widget<ListTile>(
      find.byKey(const Key('startup-workflow-credentials_login')),
    );
    expect(credentials.enabled, isFalse);
    await tester.tap(find.text('Username and password'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);

    await tester.tap(find.text('QR code'));
    await tester.pumpAndSettle();
    expect(store.values[startupWorkflowStorageKey], 'qr_login');
    expect(tester.takeException(), isNull);
  });
}
