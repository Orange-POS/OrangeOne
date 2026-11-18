import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/session/session_lifecycle.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/features/startup/presentation/providers/startup_configuration_providers.dart';

/// The identity compatibility and capability decisions belong to: the sign-in
/// method plus the session identity (environment, POS server, company, user,
/// session family), or the Demo Mode sample. Token refresh keeps it; another
/// session, server, method or sample is a replacement.
final Override capabilityScopeOverride = capabilityScopeProvider.overrideWith((
  ref,
) {
  final demo = ref.watch(demoLoginProvider);
  if (demo != null) return demo.scope;
  final identity = ref.watch(readCacheIdentityProvider);
  if (identity == null) return null;
  final method = ref.watch(
    startupConfigurationControllerProvider.select(
      (configuration) => configuration.effectiveMethod,
    ),
  );
  return '${method.storageValue}|$identity';
});

/// The session controller and Demo Mode as a [SessionLifecycle]. The object
/// lives as long as the app and reads the current state on every access;
/// listeners are notified when either changes.
final Override sessionLifecycleOverride = sessionLifecycleProvider.overrideWith(
  (ref) {
    ref
      ..listen(sessionControllerProvider, (previous, next) {
        ref.notifyListeners();
      })
      ..listen(demoLoginProvider, (previous, next) => ref.notifyListeners());
    return _AppSessionLifecycle(ref);
  },
);

class _AppSessionLifecycle implements SessionLifecycle {
  const new(this._ref);

  final Ref _ref;

  @override
  bool get signedOut {
    if (_ref.read(demoLoginProvider) != null) return false;
    final auth = _ref.read(sessionControllerProvider);
    if (auth.isLoading) return false;
    if (auth.hasError) {
      // A failed QR sign-in leaves nothing stored; a storage failure may
      // still hold credentials and keeps the login blocked.
      final error = auth.error;
      return error is! AppFailure || error.kind != FailureKind.storage;
    }
    return auth.value == null;
  }

  @override
  Future<bool> signOut() async {
    if (_ref.read(demoLoginProvider) != null) {
      _ref.read(demoLoginProvider.notifier).signOut();
      return true;
    }
    await _ref.read(sessionControllerProvider.notifier).signOut();
    final auth = _ref.read(sessionControllerProvider);
    return !auth.isLoading && !auth.hasError && auth.value == null;
  }
}
