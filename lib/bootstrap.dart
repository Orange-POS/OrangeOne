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

void bootstrap(AppEnvironment environment) {
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
  // Never pass raw framework errors, exceptions or stacks to an output sink.
  FlutterError.onError = (_) => logger.event(LogEvent.frameworkFailure);
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.event(LogEvent.platformFailure);
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
