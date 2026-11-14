import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/errors/app_failure.dart';

/// Fixed event vocabulary: no free-text messages, payloads, URLs or exceptions.
enum LogEvent {
  startup,
  frameworkFailure,
  platformFailure,
  monitoringUnavailable,
  rpcStarted,
  rpcSucceeded,
  rpcFailed,
}

class AppLogger {
  new({
    required this.environment,
    required bool enabled,
    required bool debugBuild,
    void Function(String)? sink,
  }) : _enabled =
           enabled && debugBuild && environment != AppEnvironment.production,
       _sink = sink ?? _write;

  final AppEnvironment environment;
  final bool _enabled;
  final void Function(String) _sink;
  static void _write(String record) => developer.log(record, name: 'orangeone');

  void event(
    LogEvent event, {
    int? requestId,
    int? elapsedMs,
    FailureKind? failure,
  }) {
    if (!_enabled) return;
    _sink(
      jsonEncode({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'environment': environment.name,
        'event': event.name,
        'request_id': ?requestId,
        'elapsed_ms': ?elapsedMs,
        if (failure != null) 'failure_kind': failure.name,
      }),
    );
  }
}

final appLoggerProvider = Provider<AppLogger>((ref) {
  final settings = ref.watch(applicationSettingsProvider);
  return AppLogger(
    environment: settings.environment,
    enabled: settings.loggingEnabled,
    debugBuild: kDebugMode,
  );
}, name: 'appLoggerProvider');
