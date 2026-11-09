import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class StartupConfigurationController extends Notifier<StartupConfiguration> {
  @override
  StartupConfiguration build() => ref.watch(savedStartupConfigurationProvider);

  /// Selects [workflow] and saves it for the next start. Returns false for a
  /// workflow this build cannot run. A storage failure keeps the selection
  /// for this run only.
  Future<bool> select(StartupWorkflow workflow) async {
    if (!workflow.available) return false;
    final configuration = StartupConfiguration(workflow: workflow);
    state = configuration;
    final repository = ref.read(startupConfigurationRepositoryProvider);
    try {
      await repository.save(configuration);
    } on Exception {
      // Applied until restart.
    }
    return true;
  }
}
