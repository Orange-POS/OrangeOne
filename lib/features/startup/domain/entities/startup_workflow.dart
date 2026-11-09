/// How the app signs in after a start without a session. The selected
/// workflow is the starting component the bootstrap resolver opens.
///
/// A workflow is [available] only when the app has a confirmed backend
/// contract for it. Credentials sign-in is registered for the planned
/// workflow, but the Mobile API has no credentials endpoint yet, so it
/// cannot be selected.
enum StartupWorkflow {
  qrLogin(storageValue: 'qr_login', available: true),
  credentialsLogin(storageValue: 'credentials_login', available: false);

  new({required this.storageValue, required this.available});

  /// Stable value kept in the device's saved configuration.
  final String storageValue;
  final bool available;

  /// The workflow saved as [value], or null when unknown.
  static StartupWorkflow? fromStorage(String? value) {
    for (final workflow in values) {
      if (workflow.storageValue == value) return workflow;
    }
    return null;
  }
}

/// The saved startup configuration.
class StartupConfiguration {
  const new({this.workflow = StartupWorkflow.qrLogin});

  /// Used when nothing is saved, the saved value is unknown or no longer
  /// available, or the storage cannot be read.
  static const fallback = StartupConfiguration();

  final StartupWorkflow workflow;

  /// [workflow] when it can run in this build, else the fallback.
  StartupWorkflow get effectiveWorkflow =>
      workflow.available ? workflow : fallback.workflow;
}
