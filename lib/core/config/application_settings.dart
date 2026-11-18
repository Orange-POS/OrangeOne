import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';

/// Nonsecret build settings. QR authentication still selects the POS origin.
class ApplicationSettings {
  const new({
    required this.environment,
    required this.baseUrl,
    required this.connectTimeout,
    required this.responseTimeout,
    required this.loggingEnabled,
    required this.diagnosticsEnabled,
    this.crashTestEnabled = false,
  });

  factory parse(
    AppEnvironment environment,
    Map<String, String> values, {
    required bool debugBuild,
  }) {
    const invalid = AppFailure(
      FailureKind.configuration,
      'Application configuration is invalid. Contact your administrator.',
    );
    final marker = values['APP_ENVIRONMENT'];
    if (marker != null && marker != environment.name) throw invalid;
    Duration timeout(String key, int fallback) {
      final raw = values[key];
      final value = raw == null ? fallback : int.tryParse(raw);
      if (value == null || value <= 0 || value > 600000) throw invalid;
      return Duration(milliseconds: value);
    }

    final baseUrl = values['ODOO_BASE_URL'] ?? '';
    if (baseUrl.isNotEmpty) {
      final uri = Uri.tryParse(baseUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.port <= 0 ||
          uri.port > 65535 ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          !['https', 'http'].contains(uri.scheme)) {
        throw invalid;
      }
    } else if (values.containsKey('ODOO_BASE_URL')) {
      // Omit the origin for QR discovery; explicit empty values are invalid.
      throw invalid;
    }
    final logging = values['APP_DEBUG_LOGGING'];
    if (logging != null && logging != 'true' && logging != 'false') {
      throw invalid;
    }
    final nonProductionDebug =
        debugBuild && environment != AppEnvironment.production;
    return ApplicationSettings(
      environment: environment,
      baseUrl: baseUrl,
      connectTimeout: timeout('ODOO_CONNECT_TIMEOUT_MS', 15000),
      responseTimeout: timeout('ODOO_RESPONSE_TIMEOUT_MS', 20000),
      loggingEnabled:
          nonProductionDebug &&
          (logging == 'true' ||
              (logging == null && environment == AppEnvironment.development)),
      diagnosticsEnabled:
          debugBuild && environment == AppEnvironment.development,
      // Flavor only (not build mode): the TestFlight/APK DEV build must be able
      // to verify symbolicated reports. STG and PROD never get the control.
      crashTestEnabled: environment == AppEnvironment.development,
    );
  }

  factory fromBuild(AppEnvironment environment) => ApplicationSettings.parse(
    environment,
    {
      if (const bool.hasEnvironment('APP_ENVIRONMENT'))
        'APP_ENVIRONMENT': const String.fromEnvironment('APP_ENVIRONMENT'),
      if (const bool.hasEnvironment('ODOO_BASE_URL'))
        'ODOO_BASE_URL': const String.fromEnvironment('ODOO_BASE_URL'),
      if (const bool.hasEnvironment('ODOO_CONNECT_TIMEOUT_MS'))
        'ODOO_CONNECT_TIMEOUT_MS': const String.fromEnvironment(
          'ODOO_CONNECT_TIMEOUT_MS',
        ),
      if (const bool.hasEnvironment('ODOO_RESPONSE_TIMEOUT_MS'))
        'ODOO_RESPONSE_TIMEOUT_MS': const String.fromEnvironment(
          'ODOO_RESPONSE_TIMEOUT_MS',
        ),
      if (const bool.hasEnvironment('APP_DEBUG_LOGGING'))
        'APP_DEBUG_LOGGING': const String.fromEnvironment('APP_DEBUG_LOGGING'),
    },
    debugBuild: kDebugMode,
  );

  final AppEnvironment environment;
  final String baseUrl;
  final Duration connectTimeout;
  final Duration responseTimeout;
  final bool loggingEnabled;
  final bool diagnosticsEnabled;

  /// Development-only Crashlytics verification (Settings > Trigger the Crash).
  final bool crashTestEnabled;
}

final applicationSettingsProvider = Provider<ApplicationSettings>(
  (ref) => ApplicationSettings.fromBuild(ref.watch(environmentProvider)),
  name: 'applicationSettingsProvider',
);

// Fail closed outside the configured application bootstrap (including tests).
final developmentDiagnosticsProvider = Provider<bool>(
  (ref) => false,
  name: 'developmentDiagnosticsProvider',
);

/// Whether the Settings screen and its crash test exist in this build.
/// Closed unless the bootstrap enables it for the development flavor.
final crashTestControlsProvider = Provider<bool>(
  (ref) => false,
  name: 'crashTestControlsProvider',
);
