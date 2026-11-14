import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/capabilities/api_contract.dart';
import 'package:orange_one/core/capabilities/session_permissions.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/core/network/idempotency_keys.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/network/pending_writes.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/core/storage/read_cache_secret.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/features/discounts/data/data_sources/discount_remote_data_source.dart';
import 'package:orange_one/features/discounts/data/repositories/odoo_discount_repository.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';
import 'package:orange_one/features/home/data/repositories/recent_scans_repositories.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/providers/recent_scans_providers.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/data/repositories/product_cache_synchronizer.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';

/// The signed-in session for data wiring, or null while signed out, loading
/// or failed. Token refresh keeps the same [AuthSession] instance, so
/// dependents are not rebuilt when the access token changes.
final activeSessionProvider = Provider<AuthSession?>((ref) {
  final auth = ref.watch(sessionControllerProvider);
  return auth.hasError || auth.isLoading ? null : auth.value;
}, name: 'activeSessionProvider');

/// Offline cache identity: environment, POS server, company, user and the
/// authenticated session (token family). It never contains a token, so
/// refreshing the access token keeps the cache, while another session,
/// server or flavor gets separate, unreadable data.
String readCacheIdentity(AppEnvironment environment, AuthSession session) =>
    '${environment.name}|${session.apiBase}|${session.companyId}|'
    '${session.userId}|${session.sessionId}';

final readCacheIdentityProvider = Provider<String?>((ref) {
  final session = ref.watch(activeSessionProvider);
  if (session == null) return null;
  return readCacheIdentity(
    ref.watch(apiConfigurationProvider.select((config) => config.environment)),
    session,
  );
}, name: 'readCacheIdentityProvider');

/// Unset-stock flags belong to the session identity: logout, expiry,
/// authentication rejection or a replacement session resets them.
final Override unsetStockScopeOverride = unsetStockScopeProvider.overrideWith(
  (ref) =>
      ref.watch(demoLoginProvider)?.scope ??
      ref.watch(readCacheIdentityProvider),
);

/// Reads tokens from the session controller at request time.
class _SessionTokens implements AccessTokenSource {
  const new(this._controller);
  final SessionController _controller;

  @override
  Future<String> accessToken() => _controller.accessToken();

  @override
  Future<String> refreshAccessToken(String rejectedToken) =>
      _controller.refreshAccessToken(rejectedToken);
}

/// Authenticated Mobile API v2 client for the signed-in session.
final Override authenticatedMobileApiOverride = authenticatedMobileApiProvider
    .overrideWith((ref) {
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw invalidSession;
      return AuthenticatedMobileApi(
        ref.watch(mobileApiClientProvider),
        apiBase: session.apiBase,
        tokens: _SessionTokens(ref.read(sessionControllerProvider.notifier)),
      );
    });

/// The signed-in shop's features from its own `GET /meta`, read once per
/// session: another QR sign-in (another shop or session) reads them again,
/// so shops never share features. A failure falls back to the unconfirmed
/// baseline; a screen that gates a feature reads again when it opens (even
/// while an earlier screen still listens). MobileApiClient reports failures
/// as for any API call. Demo Mode supports every feature it implements.
final Override backendFeaturesOverride = backendFeaturesProvider.overrideWith((
  ref,
) async {
  if (ref.watch(demoLoginProvider) != null) {
    return BackendFeatures({
      ...BackendFeatures.baseline.names,
      BackendFeatures.stockMovements,
    }, confirmed: true);
  }
  final session = ref.watch(activeSessionProvider);
  if (session == null) return BackendFeatures.baseline;
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  try {
    final response = await ref
        .watch(authenticatedMobileApiProvider)
        .send(MobileApiMethod.get, '/meta', cancelToken: cancel);
    final features = BackendFeatures.fromMeta(response.data);
    // Keep the answer for the rest of this session.
    ref.keepAlive();
    return features;
  } on AppFailure catch (failure) {
    // Definitive refusals block the session's screens (compatibility
    // check); every other failure degrades to the unconfirmed baseline.
    if (failure.kind == FailureKind.upgradeRequired) {
      return BackendFeatures.refused(BackendRefusal.appUpgradeRequired);
    }
    if (failure.code == 'MAINTENANCE') {
      return BackendFeatures.refused(BackendRefusal.maintenance);
    }
    return BackendFeatures.baseline;
  }
});

/// The signed-in user's permissions for the Feature Resolver. Demo Mode and
/// a signed-out app have none to report (never restricting).
final Override sessionPermissionsOverride = sessionPermissionsProvider
    .overrideWith((ref) {
      if (ref.watch(demoLoginProvider) != null) {
        return SessionPermissions.unknown;
      }
      final session = ref.watch(activeSessionProvider);
      return session == null
          ? SessionPermissions.unknown
          : SessionPermissions(session.permissions);
    });

final Override productDetailsRepositoryOverride =
    productDetailsRepositoryProvider.overrideWith((ref) {
      // A Demo Mode sign-in never reaches the session, network or cache.
      if (ref.watch(demoLoginProvider) != null) {
        return ref.watch(demoProductDetailsRepositoryProvider);
      }
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw invalidSession;
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      // Contract adapter: one data implementation per supported contract.
      return switch (ref.watch(apiContractProvider)) {
        ApiContract.mobileV1 => OdooProductDetailsRepository(
          ProductCatalogRemoteDataSource(
            ref.watch(authenticatedMobileApiProvider),
            cancelToken: cancel,
          ),
          cache: ref.watch(readCacheProvider),
          // Session-lived: closing the product screens disposes this
          // repository, never the key of a write with an unknown outcome.
          idempotencyKeys: ref.watch(idempotencyKeysProvider),
          onSessionRejected: () async {
            if (ref.mounted &&
                identical(ref.read(sessionControllerProvider).value, session)) {
              await ref.read(sessionControllerProvider.notifier).signOut();
            }
          },
        ),
      };
    });

/// Keys of writes whose outcome is unknown belong to one session identity,
/// like the server's idempotency records (per token family). Another shop,
/// user or session, logout or expiry start with none.
final Override idempotencyKeysOverride = idempotencyKeysProvider.overrideWith((
  ref,
) {
  ref.watch(readCacheIdentityProvider);
  return IdempotencyKeys();
});

/// Unresolved creates belong to one session identity (environment, server,
/// company, user, token family), like the server's idempotency records
/// (per token family). Another shop, user or session, logout or expiry get
/// a new, empty store; within the session it outlives forms, controllers
/// and repository rebuilds.
final Override pendingWritesOverride = pendingWritesProvider.overrideWith((
  ref,
) {
  ref.watch(readCacheIdentityProvider);
  return PendingWrites(now: ref.watch(utcNowProvider));
});

/// Product discounts of the signed-in shop. Mobile API 1.1 adds the
/// discount endpoints to the v1 contract without changing it, so the v1
/// adapter serves them; the Feature Resolver decides whether they are used
/// at all. Demo Mode has no discount data, so the feature stays hidden there.
final Override discountRepositoryOverride = discountRepositoryProvider
    .overrideWith((ref) {
      if (ref.watch(demoLoginProvider) != null) throw discountUnavailable;
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw invalidSession;
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return switch (ref.watch(apiContractProvider)) {
        ApiContract.mobileV1 => OdooDiscountRepository(
          DiscountRemoteDataSource(
            ref.watch(authenticatedMobileApiProvider),
            cancelToken: cancel,
          ),
          pendingWrites: ref.watch(pendingWritesProvider),
          idempotencyKeys: ref.watch(idempotencyKeysProvider),
          onSessionRejected: () async {
            if (ref.mounted &&
                identical(ref.read(sessionControllerProvider).value, session)) {
              await ref.read(sessionControllerProvider.notifier).signOut();
            }
          },
        ),
      };
    });

/// Cross-feature composition belongs to app, not either feature's internals.
final Override productRepositoryOverride = productRepositoryProvider
    .overrideWith((ref) {
      if (ref.watch(demoLoginProvider) != null) {
        return ref.watch(demoProductRepositoryProvider);
      }
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw invalidSession;
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      // Contract adapter: one data implementation per supported contract.
      return switch (ref.watch(apiContractProvider)) {
        ApiContract.mobileV1 => OdooProductRepository(
          ProductRemoteDataSource(
            ref.watch(authenticatedMobileApiProvider),
            cancelToken: cancel,
          ),
          cache: ref.watch(readCacheProvider),
          onSessionRejected: () async {
            if (!ref.mounted) return;
            final current = ref.read(sessionControllerProvider).value;
            if (identical(current, session)) {
              await ref.read(sessionControllerProvider.notifier).signOut();
            }
          },
        ),
      };
    });

/// Recent scans live in the session's encrypted cache: they survive restarts
/// and are isolated per session. The cache is null while signed out.
final Override recentScansRepositoryOverride = recentScansRepositoryProvider
    .overrideWith(
      (ref) => ref.watch(demoLoginProvider) != null
          ? ref.watch(demoRecentScansRepositoryProvider)
          : CachedRecentScansRepository(ref.watch(readCacheProvider)),
    );

/// Network interface changes (`true` when any interface is connected).
final connectivityProvider = Provider<Stream<bool>>(
  (ref) => Connectivity().onConnectivityChanged.map(
    (values) => !values.contains(ConnectivityResult.none),
  ),
  name: 'connectivityProvider',
);

/// One encrypted cache per authenticated session identity. Logout, expiry or
/// a different session dispose it, which purges that session's records.
/// Token refresh keeps it. Its snapshots are refreshed from the change feed
/// when it opens and when connectivity returns.
final Override readCacheOverride = readCacheProvider.overrideWith((ref) {
  final identity = ref.watch(readCacheIdentityProvider);
  if (identity == null) return null;
  final session = ref.watch(activeSessionProvider);
  final secrets = ReadCacheSecret(
    ref.watch(secretStoreProvider),
    environment: ref.watch(
      apiConfigurationProvider.select((config) => config.environment.name),
    ),
  );
  final cache = EncryptedReadCache(
    ref.watch(readCacheDatabaseProvider),
    sessionSecret: identity,
    keySecret: () => secrets.secretFor(identity),
  );
  // Rows of sessions that never closed their cache (the app was stopped)
  // or of an older key are removed once this session's key is known.
  unawaited(cache.purgeOtherOwners());
  final cancel = CancelToken();
  final sync = ProductCacheSynchronizer(
    ProductCatalogRemoteDataSource(
      ref.watch(authenticatedMobileApiProvider),
      cancelToken: cancel,
    ),
    cache,
    onSessionRejected: () async {
      // A stale rejection must not sign out a replacement session.
      if (ref.mounted &&
          identical(ref.read(sessionControllerProvider).value, session)) {
        await ref.read(sessionControllerProvider.notifier).signOut();
      }
    },
  );
  final subscription = ref
      .watch(connectivityProvider)
      .listen((connected) => cache.connectionChanged(connected: connected));
  // Refresh snapshots kept from a previous run, and again on recovery.
  final recovery = cache.recovery.listen((_) => unawaited(sync.sync()));
  unawaited(sync.sync());
  ref.onDispose(() {
    cancel.cancel();
    unawaited(subscription.cancel());
    unawaited(recovery.cancel());
    // The session ended: its rows are purged first, then its key secret
    // goes too (best effort; another session's secret is never deleted).
    unawaited(
      cache
          .close()
          .whenComplete(() => secrets.deleteFor(identity))
          .then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
  });
  return cache;
});
