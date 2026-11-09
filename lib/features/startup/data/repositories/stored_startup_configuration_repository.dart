import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/domain/repositories/startup_configuration_repository.dart';

/// Storage key. The value is not a secret; like the language preference it
/// reuses the injectable [SecretStore], so no extra storage dependency.
const startupWorkflowStorageKey = 'orangeone.startup_workflow';

class StoredStartupConfigurationRepository
    implements StartupConfigurationRepository {
  const new(this._store);

  final SecretStore _store;

  @override
  Future<StartupConfiguration> load() async {
    final workflow = StartupWorkflow.fromStorage(
      await _store.read(startupWorkflowStorageKey),
    );
    return workflow == null
        ? StartupConfiguration.fallback
        : StartupConfiguration(workflow: workflow);
  }

  @override
  Future<void> save(StartupConfiguration configuration) => _store.write(
    startupWorkflowStorageKey,
    configuration.workflow.storageValue,
  );
}
