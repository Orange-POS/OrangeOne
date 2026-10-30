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
///
/// Crashlytics custom keys are shared state, so reports run one at a time in
/// call order: each event writes all of its keys (clearing absent ones) and
/// is recorded before the next one starts. Callers never wait for it.
class FirebaseCrashReporter implements CrashReporter {
  new(
    this._crashlytics, {
    required this._environment,
    this.throttle = const Duration(minutes: 5),
    this.reportTimeout = const Duration(seconds: 10),
    DateTime Function()? clock,
    String Function()? newReference,
  }) : _clock = clock ?? DateTime.now,
       _newReference = newReference ?? ErrorReference.generate;

  final FirebaseCrashlytics _crashlytics;
  final AppEnvironment _environment;
  final Duration throttle;

  /// Longest wait for one queued step, so a stalled plugin call cannot stop
  /// every later report.
  final Duration reportTimeout;
  final DateTime Function() _clock;
  final String Function() _newReference;
  final _lastReported = <String, DateTime>{};
  Future<void> _queue = Future<void>.value();

  void _guard(void Function() action) {
    try {
      action();
    } on Object {
      // Monitoring failures never reach the application.
    }
  }

  void _enqueue(Future<void> Function() action) {
    try {
      _queue = _queue
          .then((_) => action().timeout(reportTimeout))
          .catchError((Object _) {});
    } on Object {
      // Monitoring failures never reach the application.
    }
  }

  /// Writes every per-event key, so an event never inherits another event's
  /// reference, operation or optional identifiers.
  Future<void> _setEventKeys({
    String errorId = '',
    String failureKind = '',
    String operation = '',
    String? apiCode,
    String? requestId,
  }) async {
    await _crashlytics.setCustomKey('error_id', errorId);
    await _crashlytics.setCustomKey('failure_kind', failureKind);
    await _crashlytics.setCustomKey('operation', operation);
    await _crashlytics.setCustomKey('api_code', apiCode ?? '');
    await _crashlytics.setCustomKey('request_id', requestId ?? '');
  }

  @override
  void recordFatal(Object error, StackTrace stack) {
    _enqueue(() async {
      await _setEventKeys();
      await _crashlytics.recordError(
        SanitizedReport('Unhandled ${error.runtimeType}'),
        stack,
        reason: 'unhandled_error',
        fatal: true,
      );
    });
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
    _enqueue(() async {
      await _setEventKeys(
        errorId: reference,
        failureKind: failure.kind.name,
        operation: operation,
        apiCode: failure.code,
        requestId: failure.requestId,
      );
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
    _enqueue(() async {
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
    _enqueue(() async {
      await _setEventKeys(errorId: reference);
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
///
/// [timeout] bounds the whole sequence (Firebase initialization and the
/// collection setting). After it expires the sequence is abandoned: a late
/// completion takes no further step and a late error is ignored.
Future<CrashReporter> initializeCrashReporting({
  required AppEnvironment environment,
  required AppLogger logger,
  Future<Object?> Function()? initialize,
  FirebaseCrashlytics Function()? crashlytics,
  Duration timeout = const Duration(seconds: 3),
}) async {
  var abandoned = false;

  Future<CrashReporter?> start() async {
    await (initialize?.call() ?? Firebase.initializeApp());
    if (abandoned) return null;
    final instance = crashlytics?.call() ?? FirebaseCrashlytics.instance;
    // Staging and production report only from release/profile builds; the
    // development flavor also reports from debug builds (Development project).
    await instance.setCrashlyticsCollectionEnabled(
      !kDebugMode || environment == AppEnvironment.development,
    );
    if (abandoned) return null;
    return FirebaseCrashReporter(instance, environment: environment)
      ..setIdentity(null);
  }

  final sequence = start();

  try {
    final reporter = await sequence.timeout(timeout);
    if (reporter != null) return reporter;
  } on Object {
    abandoned = true;
    sequence.ignore();
  }

  logger.event(LogEvent.monitoringUnavailable);
  return const NoopCrashReporter();
}
