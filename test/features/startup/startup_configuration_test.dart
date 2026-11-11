import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/session/session_lifecycle.dart';
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

/// A controllable session: [signOut] waits for [cleanup] when set and
/// reports [cleared].
class _Lifecycle implements SessionLifecycle {
  @override
  bool signedOut = false;
  bool cleared = true;
  Completer<void>? cleanup;
  int signOuts = 0;

  @override
  Future<bool> signOut() async {
    signOuts++;
    await cleanup?.future;
    if (cleared) signedOut = true;
    return cleared;
  }
}

String _saved(String method, {int schema = 2}) =>
    jsonEncode({'schema': schema, 'auth_method': method});

void main() {
  group('bootstrap load', () {
    test(
      'nothing saved, an unknown value or a read failure: QR login',
      () async {
        final store = MemorySecretStore();
        final repository = StoredStartupConfigurationRepository(store);
        expect(
          (await loadStartupConfiguration(repository)).method,
          AuthenticationMethod.qrLogin,
        );
        store.values[startupConfigurationStorageKey] = _saved('smart_card');
        expect(
          (await loadStartupConfiguration(repository)).method,
          AuthenticationMethod.qrLogin,
        );
        store.values[startupConfigurationStorageKey] = 'not json';
        expect(
          (await loadStartupConfiguration(repository)).method,
          AuthenticationMethod.qrLogin,
        );
        store.failure = storageFailure;
        expect(
          (await loadStartupConfiguration(repository)).method,
          AuthenticationMethod.qrLogin,
        );
      },
    );

    test('a newer schema this build does not know falls back', () async {
      final store = MemorySecretStore()
        ..values[startupConfigurationStorageKey] = _saved('oidc', schema: 3);
      final loaded = await loadStartupConfiguration(
        StoredStartupConfigurationRepository(store),
      );
      expect(loaded.method, AuthenticationMethod.qrLogin);
    });

    test('schema 1 (bare workflow value) is migrated once', () async {
      final store = MemorySecretStore()
        ..values[startupWorkflowStorageKey] = 'credentials_login';
      final loaded = await loadStartupConfiguration(
        StoredStartupConfigurationRepository(store),
      );
      // Username and password stays its own method, never OIDC.
      expect(loaded.method, AuthenticationMethod.credentials);
      expect(loaded.effectiveMethod, AuthenticationMethod.qrLogin);
      expect(store.values.containsKey(startupWorkflowStorageKey), isFalse);
      expect(jsonDecode(store.values[startupConfigurationStorageKey]!), {
        'schema': 2,
        'auth_method': 'credentials_login',
      });
    });

    test('a saved method is restored at the next start', () async {
      final store = MemorySecretStore();
      await StoredStartupConfigurationRepository(store)
          .save(StartupConfiguration.fallback);
      final loaded = await loadStartupConfiguration(
        StoredStartupConfigurationRepository(store),
      );
      expect(loaded.method, AuthenticationMethod.qrLogin);
    });

    testWidgets('a stalled store never blocks the start', (tester) async {
      final loading = loadStartupConfiguration(_StalledRepository());
      await tester.pump(startupConfigurationLoadLimit);
      expect((await loading).method, AuthenticationMethod.qrLogin);
    });

    test('saved methods without a confirmed contract run QR login', () {
      for (final method in [
        AuthenticationMethod.oidc,
        AuthenticationMethod.credentials,
      ]) {
        expect(method.available, isFalse);
        expect(
          StartupConfiguration(method: method).effectiveMethod,
          AuthenticationMethod.qrLogin,
        );
      }
    });

    test('the controller starts from the bootstrap configuration', () {
      const saved = StartupConfiguration(method: AuthenticationMethod.oidc);
      final container = ProviderContainer.test(
        overrides: [savedStartupConfigurationProvider.overrideWithValue(saved)],
      );
      expect(
        container.read(startupConfigurationControllerProvider).method,
        AuthenticationMethod.oidc,
      );
    });
  });

  group('selection', () {
    /// Starts from a saved method this build cannot run, so that QR login is
    /// a real change.
    ProviderContainer containerWith(
      MemorySecretStore store, {
      SessionLifecycle? lifecycle,
    }) => ProviderContainer.test(
      overrides: [
        secretStoreProvider.overrideWithValue(store),
        savedStartupConfigurationProvider.overrideWithValue(
          const StartupConfiguration(method: AuthenticationMethod.oidc),
        ),
        if (lifecycle != null)
          sessionLifecycleProvider.overrideWithValue(lifecycle),
      ],
    );

    test('signed out: an available method is selected and saved', () async {
      final store = MemorySecretStore();
      final container = containerWith(store);
      final controller = container.read(
        startupConfigurationControllerProvider.notifier,
      );
      expect(
        await controller.select(AuthenticationMethod.qrLogin),
        ConfigurationChange.applied,
      );
      expect(store.values[startupConfigurationStorageKey], _saved('qr_login'));
      expect(
        await controller.select(AuthenticationMethod.qrLogin),
        ConfigurationChange.unchanged,
      );
    });

    test('a method without a confirmed contract is refused', () async {
      final store = MemorySecretStore();
      final container = ProviderContainer.test(
        overrides: [secretStoreProvider.overrideWithValue(store)],
      );
      final controller = container.read(
        startupConfigurationControllerProvider.notifier,
      );
      for (final method in [
        AuthenticationMethod.oidc,
        AuthenticationMethod.credentials,
      ]) {
        expect(
          await controller.select(method),
          ConfigurationChange.unavailable,
        );
        expect(
          await controller.switchTo(method),
          ConfigurationChange.unavailable,
        );
      }
      expect(store.writes, 0);
    });

    test(
      'signed in: select never changes the method under the session',
      () async {
        final store = MemorySecretStore();
        final lifecycle = _Lifecycle();
        final container = containerWith(store, lifecycle: lifecycle);
        expect(
          await container
              .read(startupConfigurationControllerProvider.notifier)
              .select(AuthenticationMethod.qrLogin),
          ConfigurationChange.signOutRequired,
        );
        expect(lifecycle.signOuts, 0);
        expect(store.writes, 0);
        expect(
          container.read(startupConfigurationControllerProvider).method,
          AuthenticationMethod.oidc,
        );
      },
    );

    test('switchTo signs out first and applies only after cleanup', () async {
      final store = MemorySecretStore();
      final lifecycle = _Lifecycle()..cleanup = Completer<void>();
      final container = containerWith(store, lifecycle: lifecycle);
      final switching = container
          .read(startupConfigurationControllerProvider.notifier)
          .switchTo(AuthenticationMethod.qrLogin);
      await Future<void>.delayed(Duration.zero);
      // Credentials are not yet deleted: nothing has changed.
      expect(lifecycle.signOuts, 1);
      expect(store.writes, 0);
      expect(
        container.read(startupConfigurationControllerProvider).method,
        AuthenticationMethod.oidc,
      );
      lifecycle.cleanup!.complete();
      expect(await switching, ConfigurationChange.applied);
      expect(
        container.read(startupConfigurationControllerProvider).method,
        AuthenticationMethod.qrLogin,
      );
      expect(store.values[startupConfigurationStorageKey], _saved('qr_login'));
    });

    test('a secure-storage cleanup failure keeps the old method', () async {
      final store = MemorySecretStore();
      final lifecycle = _Lifecycle()..cleared = false;
      final container = containerWith(store, lifecycle: lifecycle);
      expect(
        await container
            .read(startupConfigurationControllerProvider.notifier)
            .switchTo(AuthenticationMethod.qrLogin),
        ConfigurationChange.cleanupFailed,
      );
      expect(store.writes, 0);
      expect(
        container.read(startupConfigurationControllerProvider).method,
        AuthenticationMethod.oidc,
      );
    });

    test('an interrupted switch is superseded by the newer request', () async {
      final store = MemorySecretStore();
      final lifecycle = _Lifecycle()..cleanup = Completer<void>();
      final container = containerWith(store, lifecycle: lifecycle);
      final controller = container.read(
        startupConfigurationControllerProvider.notifier,
      );
      final first = controller.switchTo(AuthenticationMethod.qrLogin);
      await Future<void>.delayed(Duration.zero);
      final second = controller.switchTo(AuthenticationMethod.qrLogin);
      lifecycle.cleanup!.complete();
      expect(await first, ConfigurationChange.superseded);
      expect(await second, ConfigurationChange.applied);
      expect(store.writes, 1);
    });

    test('a save failure keeps the selection for this run', () async {
      final store = MemorySecretStore()..failure = storageFailure;
      final container = containerWith(store);
      expect(
        await container
            .read(startupConfigurationControllerProvider.notifier)
            .select(AuthenticationMethod.qrLogin),
        ConfigurationChange.applied,
      );
      expect(
        container.read(startupConfigurationControllerProvider).method,
        AuthenticationMethod.qrLogin,
      );
    });

    test('restart after a saved change starts with the new method', () async {
      final store = MemorySecretStore();
      final container = containerWith(store);
      await container
          .read(startupConfigurationControllerProvider.notifier)
          .select(AuthenticationMethod.qrLogin);
      container.dispose();
      final restarted = await loadStartupConfiguration(
        StoredStartupConfigurationRepository(store),
      );
      expect(restarted.method, AuthenticationMethod.qrLogin);
    });
  });

  Future<MemorySecretStore> pumpSection(
    WidgetTester tester, {
    SessionLifecycle? lifecycle,
  }) async {
    final store = MemorySecretStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secretStoreProvider.overrideWithValue(store),
          savedStartupConfigurationProvider.overrideWithValue(
            const StartupConfiguration(method: AuthenticationMethod.oidc),
          ),
          if (lifecycle != null)
            sessionLifecycleProvider.overrideWithValue(lifecycle),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StartupWorkflowSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('the section lists the methods; unavailable ones cannot be '
      'chosen', (tester) async {
    final store = await pumpSection(tester);
    expect(find.text('QR code'), findsOneWidget);
    expect(find.text('Company sign-in (OIDC)'), findsOneWidget);
    expect(find.text('Username and password'), findsOneWidget);
    expect(find.text('Not available yet'), findsNWidgets(2));
    // The saved method cannot run here: QR login is in use.
    expect(find.byIcon(Icons.check), findsOneWidget);

    for (final key in ['oidc', 'credentials_login']) {
      final tile = tester.widget<ListTile>(
        find.byKey(Key('startup-workflow-$key')),
      );
      expect(tile.enabled, isFalse);
    }
    await tester.tap(find.text('Username and password'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);

    await tester.tap(find.text('QR code'));
    await tester.pumpAndSettle();
    expect(store.values[startupConfigurationStorageKey], _saved('qr_login'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('while signed in nothing can be changed', (tester) async {
    final store = await pumpSection(tester, lifecycle: _Lifecycle());
    expect(find.text('Sign out to change the sign-in method.'), findsOneWidget);
    final qr = tester.widget<ListTile>(
      find.byKey(const Key('startup-workflow-qr_login')),
    );
    expect(qr.enabled, isFalse);
    await tester.tap(find.text('QR code'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
  });
}
