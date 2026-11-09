import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';

/// Device-local, nonsecret startup configuration.
abstract interface class StartupConfigurationRepository {
  /// The saved configuration, or [StartupConfiguration.fallback].
  Future<StartupConfiguration> load();

  Future<void> save(StartupConfiguration configuration);
}
