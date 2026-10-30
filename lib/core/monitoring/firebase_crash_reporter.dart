import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/logging/app_logger.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/monitoring/error_reference.dart';
import 'package:orange_one/core/monitoring/reportable_failure.dart';

/// What Crashlytics receives instead of the original exception: its type and
/// fixed vocabulary only, never a message that could contain a URL, token,
/// barcode or customer data.
class SanitizedReport implements Exception {
  const new(this.description);

  final String description;

  @override
  String toString() => description;
}

/// [CrashReporter] on Firebase Crashlytics. Every call is guarded: a plugin
/// failure is swallowed so monitoring can never break the application.
class FirebaseCrashReporter implements CrashReporter {
  new(
    this._crashlytics, {
    required this._environment,
    this.throttle = const Duration(minutes: 5),
    DateTime Function()? clock,
    String Function()? newReference,
  }) : _clock = clock ?? DateTime.now,
       _newReference = newReference ?? ErrorReference.generate;

  final FirebaseCrashlytics _crashlytics;
  final AppEnvironment _environment;
  final Duration throttle;
  final DateTime Function() _clock;
  final String Function() _newReference;
  final _lastReported = <String, DateTime>{};

  void _guard(void Function() action) {
    try {
      action();
    } on Object {
      // Monitoring failures never reach the application.
    }
  }

  void _guardAsync(Future<void> Function() action) {
    try {
      unawaited(action().catchError((Object _) {}));
    } on Object {
      // Monitoring failures never reach the application.
    }
  }

  @override
  void recordFatal(Object error, StackTrace stack) {
    _guardAsync(
      () => _crashlytics.recordError(
        SanitizedReport('Unhandled ${error.runtimeType}'),
        stack,
        reason: 'unhandled_error',
        fatal: true,
      ),
    );
  }

  @override
  String? recordFailure(
    AppFailure failure, {
    required String operation,
    StackTrace? stack,
  }) {
    final policy = reportPolicyFor(failure.kind);
    if (policy == ReportPolicy.never) return null;
    final key = '$operation|${failure.kind.name}';
    final now = _clock();
    if (policy == ReportPolicy.throttled) {
      final last = _lastReported[key];
      if (last != null && now.difference(last) < throttle) return null;
    }
    _lastReported[key] = now;
    final reference = _newReference();
    _guardAsync(() async {
      await _crashlytics.setCustomKey('error_id', reference);
      await _crashlytics.setCustomKey('failure_kind', failure.kind.name);
      await _crashlytics.setCustomKey('operation', operation);
      if (failure.code != null) {
        await _crashlytics.setCustomKey('api_code', failure.code!);
      }
      if (failure.requestId != null) {
        await _crashlytics.setCustomKey('request_id', failure.requestId!);
      }
      await _crashlytics.log('error_id=$reference');
      await _crashlytics.recordError(
        SanitizedReport('OrangeFailure(${failure.kind.name}, $operation)'),
        stack ?? StackTrace.current,
        reason: failure.kind.name,
      );
    });
    return reference;
  }

  @override
  void setIdentity(CrashIdentity? identity) {
    _guardAsync(() async {
      await _crashlytics.setCustomKey('environment', _environment.name);
      await _crashlytics.setCustomKey(
        'company_id',
        identity == null ? '' : '${identity.companyId}',
      );
      await _crashlytics.setCustomKey(
        'pos_config_id',
        identity == null ? '' : '${identity.posConfigId}',
      );
    });
  }

  @override
  void recordTestNonFatal() {
    final reference = _newReference();
    _guardAsync(() async {
      await _crashlytics.setCustomKey('error_id', reference);
      await _crashlytics.recordError(
        const SanitizedReport('OrangeTest(non-fatal verification)'),
        StackTrace.current,
        reason: 'verification',
      );
    });
  }

  @override
  void triggerTestCrash() => _guard(_crashlytics.crash);
}

/// Initializes Firebase and returns the reporter, or a no-op reporter when
/// Firebase is unconfigured, slow or failing: the app always starts.
Future<CrashReporter> initializeCrashReporting({
  required AppEnvironment environment,
  required AppLogger logger,
  Future<Object?> Function()? initialize,
  FirebaseCrashlytics Function()? crashlytics,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    await (initialize?.call() ?? Firebase.initializeApp()).timeout(timeout);
    final instance = crashlytics?.call() ?? FirebaseCrashlytics.instance;
    // Debug builds never report; release and profile builds of every flavor do.
    await instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    return FirebaseCrashReporter(instance, environment: environment)
      ..setIdentity(null);
  } on Object {
    logger.event(LogEvent.monitoringUnavailable);
    return const NoopCrashReporter();
  }
}
