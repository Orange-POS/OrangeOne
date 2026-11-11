import 'dart:convert';

import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';
import 'package:orange_one/features/startup/domain/repositories/startup_configuration_repository.dart';

/// Storage key of the current layout (JSON with a schema version). The value
/// is not a secret; like the language preference it reuses the injectable
/// [SecretStore], so no extra storage dependency.
const startupConfigurationStorageKey = 'orangeone.startup_configuration';

/// Schema 1: the bare workflow value (`qr_login`, `credentials_login`).
/// Read once for migration, then replaced by the current layout.
const startupWorkflowStorageKey = 'orangeone.startup_workflow';

class StoredStartupConfigurationRepository
    implements StartupConfigurationRepository {
  const new(this._store);

  final SecretStore _store;

  @override
  Future<StartupConfiguration> load() async {
    final current = await _store.read(startupConfigurationStorageKey);
    if (current != null) return _decode(current);
    final legacy = await _store.read(startupWorkflowStorageKey);
    if (legacy == null) return StartupConfiguration.fallback;
    final migrated = _configuration(AuthenticationMethod.fromStorage(legacy));
    // Best effort: a failed migration is simply repeated on the next start.
    try {
      await save(migrated);
      await _store.delete(startupWorkflowStorageKey);
    } on Exception {
      // Keep using the migrated value for this run.
    }
    return migrated;
  }

  @override
  Future<void> save(StartupConfiguration configuration) => _store.write(
    startupConfigurationStorageKey,
    jsonEncode({
      'schema': StartupConfiguration.schemaVersion,
      'auth_method': configuration.method.storageValue,
    }),
  );

  /// Unknown layouts, newer schemas and unknown methods fall back to QR
  /// login instead of guessing.
  StartupConfiguration _decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['schema'] != StartupConfiguration.schemaVersion) {
        return StartupConfiguration.fallback;
      }
      final method = value['auth_method'];
      return _configuration(
        AuthenticationMethod.fromStorage(method is String ? method : null),
      );
    } on FormatException {
      return StartupConfiguration.fallback;
    }
  }

  static StartupConfiguration _configuration(AuthenticationMethod? method) =>
      method == null
      ? StartupConfiguration.fallback
      : StartupConfiguration(method: method);
}
