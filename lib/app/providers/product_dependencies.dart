import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

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

final Override productDetailsRepositoryOverride =
    productDetailsRepositoryProvider.overrideWith((ref) {
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw invalidSession;
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return OdooProductDetailsRepository(
        ProductDetailsRemoteDataSource(
          ref.watch(jsonRpcClientProvider),
          origin: session.backendOrigin,
          token: ref.read(sessionControllerProvider.notifier).accessToken,
          cancelToken: cancel,
        ),
        cache: ref.watch(readCacheProvider),
        onSessionRejected: () async {
          if (ref.mounted &&
              identical(ref.read(sessionControllerProvider).value, session)) {
            await ref.read(sessionControllerProvider.notifier).signOut();
          }
        },
      );
    });

/// Cross-feature composition belongs to app, not either feature's internals.
final Override productRepositoryOverride = productRepositoryProvider
    .overrideWith((ref) {
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw invalidSession;
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return OdooProductRepository(
        ProductRemoteDataSource(
          ref.watch(jsonRpcClientProvider),
          origin: session.backendOrigin,
          accessToken: ref.read(sessionControllerProvider.notifier).accessToken,
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
      );
    });

/// Network interface changes (`true` when any interface is connected).
final connectivityProvider = Provider<Stream<bool>>(
  (ref) => Connectivity().onConnectivityChanged.map(
    (values) => !values.contains(ConnectivityResult.none),
  ),
  name: 'connectivityProvider',
);

/// One encrypted cache per authenticated session identity. Logout, expiry or
/// a different session dispose it, which purges that session's records.
final Override readCacheOverride = readCacheProvider.overrideWith((ref) {
  final identity = ref.watch(readCacheIdentityProvider);
  if (identity == null) return null;
  final cache = EncryptedReadCache(
    ref.watch(readCacheDatabaseProvider),
    sessionSecret: identity,
  );
  final subscription = ref
      .watch(connectivityProvider)
      .listen((connected) => cache.connectionChanged(connected: connected));
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(cache.close());
  });
  return cache;
});
