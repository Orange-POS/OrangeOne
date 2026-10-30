import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/logging/app_logger.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/monitoring/firebase_crash_reporter.dart';

Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (appFlavor != environment.name) {
    runApp(const ConfigurationErrorApp());
    return;
  }
  final ApplicationSettings settings;
  try {
    environment.validateNativeFlavor(appFlavor);
    settings = ApplicationSettings.fromBuild(environment);
  } on AppFailure {
    runApp(const ConfigurationErrorApp());
    return;
  }
  final logger = AppLogger(
    environment: environment,
    enabled: settings.loggingEnabled,
    debugBuild: kDebugMode,
  );
  // Firebase failures fall back to a no-op reporter; the app always starts.
  final reporter = await initializeCrashReporting(
    environment: environment,
    logger: logger,
  );
  // Output sinks and the logger never see raw errors; the reporter sends
  // only the error type and the stack trace.
  FlutterError.onError = (details) {
    logger.event(LogEvent.frameworkFailure);
    reporter.recordFatal(details.exception, details.stack ?? StackTrace.empty);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.event(LogEvent.platformFailure);
    reporter.recordFatal(error, stack);
    return true;
  };
  logger.event(LogEvent.startup);
  runApp(
    ProviderScope(
      overrides: [
        environmentProvider.overrideWithValue(environment),
        applicationSettingsProvider.overrideWithValue(settings),
        developmentDiagnosticsProvider.overrideWithValue(
          settings.diagnosticsEnabled,
        ),
        appLoggerProvider.overrideWithValue(logger),
        crashReporterProvider.overrideWithValue(reporter),
        crashTestControlsProvider.overrideWithValue(settings.crashTestEnabled),
        readCacheOverride,
        unsetStockScopeOverride,
        recentScansRepositoryOverride,
        authenticatedMobileApiOverride,
        productRepositoryOverride,
        productDetailsRepositoryOverride,
      ],
      child: const App(),
    ),
  );
}

/// Safe startup failure: no URLs, build values, credentials or stack traces.
class ConfigurationErrorApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Application configuration is invalid. '
              'Contact your administrator.',
            ),
          ),
        ),
      ),
    ),
  );
}
