import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/session/session_lifecycle.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/startup/data/repositories/stored_startup_configuration_repository.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/domain/repositories/startup_configuration_repository.dart';

final Provider<StartupConfigurationRepository>
startupConfigurationRepositoryProvider =
    Provider<StartupConfigurationRepository>(
      (ref) =>
          StoredStartupConfigurationRepository(ref.watch(secretStoreProvider)),
      name: 'startupConfigurationRepositoryProvider',
    );

/// Longest wait for the saved configuration before the first frame.
const startupConfigurationLoadLimit = Duration(seconds: 2);

/// Reads the saved configuration once during bootstrap. Never fails: an
/// unreadable or slow store starts with [StartupConfiguration.fallback].
Future<StartupConfiguration> loadStartupConfiguration(
  StartupConfigurationRepository repository,
) async {
  try {
    return await repository.load().timeout(startupConfigurationLoadLimit);
  } on Exception {
    return StartupConfiguration.fallback;
  }
}

/// The configuration read during bootstrap; the bootstrap overrides it.
final Provider<StartupConfiguration> savedStartupConfigurationProvider =
    Provider<StartupConfiguration>(
      (ref) => StartupConfiguration.fallback,
      name: 'savedStartupConfigurationProvider',
    );

/// The current startup configuration (container-lived). It starts from the
/// configuration read during bootstrap, so routing never waits for storage.
final startupConfigurationControllerProvider =
    NotifierProvider<StartupConfigurationController, StartupConfiguration>(
      StartupConfigurationController.new,
      name: 'startupConfigurationControllerProvider',
    );

/// The outcome of a requested sign-in method change.
enum ConfigurationChange {
  /// The method is in use (and saved, when the storage allowed it).
  applied,

  /// Already the method in use; nothing changed.
  unchanged,

  /// No confirmed backend contract in this build; nothing changed.
  unavailable,

  /// A session exists: [StartupConfigurationController.select] never
  /// changes the method under it. Use
  /// [StartupConfigurationController.switchTo] to sign out first.
  signOutRequired,

  /// Signing out could not delete the stored credentials; the method stays
  /// unchanged and the login stays blocked until the storage is cleared.
  cleanupFailed,

  /// A newer change request replaced this one while it was signing out.
  superseded,
}

/// Owns the saved sign-in method and when a change may take effect.
///
/// A change applies only while signed out: every session-owned state
/// (credentials, permissions, `/meta` capabilities, compatibility decisions,
/// read cache, recent scans, monitoring identity) is bound to the signed-in
/// session and is disposed with it, so a method only ever applies to a
/// session that was started with it. [switchTo] is the controlled
/// transition from a signed-in state: it signs out, waits until the stored
/// credentials are deleted, and only then applies the method.
class StartupConfigurationController extends Notifier<StartupConfiguration> {
  int _generation = 0;

  @override
  StartupConfiguration build() => ref.watch(savedStartupConfigurationProvider);

  /// Selects [method] while signed out and saves it for the next start. A
  /// storage failure keeps the selection for this run only.
  Future<ConfigurationChange> select(AuthenticationMethod method) async {
    if (!method.available) return ConfigurationChange.unavailable;
    if (state.method == method) return ConfigurationChange.unchanged;
    if (!ref.read(sessionLifecycleProvider).signedOut) {
      return ConfigurationChange.signOutRequired;
    }
    _generation++;
    await _apply(method);
    return ConfigurationChange.applied;
  }

  /// Signs out (when needed), then selects [method]. Pending requests of
  /// the old session are cancelled by its disposal; a stale answer cannot
  /// restore it because every session-bound provider is generation-guarded
  /// by the session identity.
  Future<ConfigurationChange> switchTo(AuthenticationMethod method) async {
    if (!method.available) return ConfigurationChange.unavailable;
    if (state.method == method) return ConfigurationChange.unchanged;
    final generation = ++_generation;
    final lifecycle = ref.read(sessionLifecycleProvider);
    if (!lifecycle.signedOut && !await lifecycle.signOut()) {
      return ref.mounted && generation == _generation
          ? ConfigurationChange.cleanupFailed
          : ConfigurationChange.superseded;
    }
    if (!ref.mounted || generation != _generation) {
      return ConfigurationChange.superseded;
    }
    if (!ref.read(sessionLifecycleProvider).signedOut) {
      // A new sign-in started meanwhile; never change it under that session.
      return ConfigurationChange.signOutRequired;
    }
    await _apply(method);
    return ConfigurationChange.applied;
  }

  Future<void> _apply(AuthenticationMethod method) async {
    final configuration = StartupConfiguration(method: method);
    state = configuration;
    try {
      await ref
          .read(startupConfigurationRepositoryProvider)
          .save(configuration);
    } on Exception {
      // Applied until restart.
    }
  }
}
