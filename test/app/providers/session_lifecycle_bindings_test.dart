import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/app/providers/session_lifecycle_bindings.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/session/session_lifecycle.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/presentation/providers/startup_configuration_providers.dart';

import '../../support/auth_fakes.dart';

/// `GET /meta` that answers only when the test completes [reply].
class _SlowMeta implements AuthenticatedMobileApi {
  final reply = Completer<Map<String, Object?>>();
  int calls = 0;
  bool cancelled = false;

  @override
  Uri get apiBase => testApiBase;

  @override
  Future<MobileApiResponse> send(
    MobileApiMethod method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? language,
    String? idempotencyKey,
    String? ifMatchVersion,
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) async {
    calls++;
    unawaited(cancelToken?.whenCancel.then((_) => cancelled = true));
    final data = await reply.future;
    if (data['refuse'] == true) {
      throw const AppFailure(
        FailureKind.upgradeRequired,
        'Update required',
        code: 'APP_UPGRADE_REQUIRED',
      );
    }
    return MobileApiResponse(statusCode: 200, data: data);
  }
}

void main() {
  late FakeAuthRepository auth;
  late _SlowMeta meta;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository()..restored = testSession;
    meta = _SlowMeta();
    container =
        ProviderContainer.test(
            overrides: [
              environmentProvider.overrideWithValue(AppEnvironment.development),
              authRepositoryProvider.overrideWithValue(auth),
              utcNowProvider.overrideWithValue(() => testNow),
              secretStoreProvider.overrideWithValue(MemorySecretStore()),
              savedStartupConfigurationProvider.overrideWithValue(
                // A saved method that is no longer available: QR fallback.
                const StartupConfiguration(method: AuthenticationMethod.oidc),
              ),
              authenticatedMobileApiProvider.overrideWith((ref) {
                if (ref.watch(activeSessionProvider) == null) {
                  throw invalidSession;
                }
                return meta;
              }),
              backendFeaturesOverride,
              capabilityScopeOverride,
              sessionLifecycleOverride,
            ],
          )
          ..listen(compatibilityProvider, (_, _) {})
          ..listen(backendFeaturesProvider, (_, _) {});
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await container.pump();
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('switching while /meta is pending signs out first; the late refusal '
      'of the old session changes nothing', () async {
    await container.read(sessionControllerProvider.future);
    await settle();
    expect(meta.calls, 1);
    final lifecycle = container.read(sessionLifecycleProvider);
    expect(lifecycle.signedOut, isFalse);
    expect(container.read(capabilityScopeProvider), startsWith('qr_login|'));

    final result = await container
        .read(startupConfigurationControllerProvider.notifier)
        .switchTo(AuthenticationMethod.qrLogin);
    expect(result, ConfigurationChange.applied);
    expect(auth.signOuts, 1);
    expect(container.read(sessionLifecycleProvider).signedOut, isTrue);
    expect(container.read(capabilityScopeProvider), isNull);
    // The pending request of the old session was cancelled.
    await settle();
    expect(meta.cancelled, isTrue);

    // Its delayed answer arrives after the switch.
    meta.reply.complete({'refuse': true});
    await settle();
    expect(
      container.read(compatibilityProvider),
      CompatibilityStatus.compatible,
    );
    expect(
      container.read(backendFeaturesProvider).value,
      same(BackendFeatures.baseline),
    );
    expect(
      container.read(startupConfigurationControllerProvider).method,
      AuthenticationMethod.qrLogin,
    );
  });

  test(
    'a secure-storage cleanup failure blocks the switch and the login',
    () async {
      await container.read(sessionControllerProvider.future);
      await settle();
      auth.failure = storageFailure;

      final result = await container
          .read(startupConfigurationControllerProvider.notifier)
          .switchTo(AuthenticationMethod.qrLogin);
      expect(result, ConfigurationChange.cleanupFailed);
      // Never claims the storage was cleared; the method is unchanged.
      final lifecycle = container.read(sessionLifecycleProvider);
      expect(lifecycle.signedOut, isFalse);
      expect(container.read(sessionControllerProvider).hasError, isTrue);
      expect(
        container.read(startupConfigurationControllerProvider).method,
        AuthenticationMethod.oidc,
      );
      // A new QR login stays blocked until the deletion succeeds.
      expect(
        await container.read(sessionControllerProvider.notifier).signIn('x'),
        isFalse,
      );
    },
  );

  test('a failed QR sign-in still counts as signed out', () async {
    await container.read(sessionControllerProvider.future);
    await container.read(sessionControllerProvider.notifier).signOut();
    auth.failure = const AppFailure(FailureKind.usedQr, 'Used');
    await container.read(sessionControllerProvider.notifier).signIn(validQr());
    expect(container.read(sessionControllerProvider).hasError, isTrue);
    expect(container.read(sessionLifecycleProvider).signedOut, isTrue);
  });
}
