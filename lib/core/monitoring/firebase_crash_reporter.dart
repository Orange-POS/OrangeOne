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

/// One queued reporting step. It is abandoned when it exceeds
/// [FirebaseCrashReporter.reportTimeout]; its remaining plugin calls are then
/// skipped, so it cannot resume after newer reports.
class _ReportStep {
  bool abandoned = false;
}

class _Abandoned implements Exception {
  const new();
}

/// [CrashReporter] on Firebase Crashlytics. Every call is guarded: a plugin
/// failure is swallowed so monitoring can never break the application.
///
/// Crashlytics custom keys are shared state, so reports run one at a time in
/// call order: each event writes all of its keys (clearing absent ones) and
/// is recorded before the next one starts. Callers never wait for it. The
/// same values travel with the event itself (`recordError` information), so
/// a plugin call that completes late cannot change what an event says.
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
  CrashIdentity? _identity;

  void _guard(void Function() action) {
    try {
      action();
    } on Object {
      // Monitoring failures never reach the application.
    }
  }

  void _enqueue(Future<void> Function(_ReportStep step) action) {
    try {
      _queue = _queue
          .then((_) {
            final step = _ReportStep();
            return action(step).timeout(
              reportTimeout,
              onTimeout: () {
                step.abandoned = true;
              },
            );
          })
          .catchError((Object _) {});
    } on Object {
      // Monitoring failures never reach the application.
    }
  }

  /// Runs one plugin call of [step], unless the step was abandoned after its
  /// timeout: a late-resuming step stops here instead of touching shared keys.
  Future<void> _call(_ReportStep step, Future<void> Function() call) async {
    if (step.abandoned) throw const _Abandoned();
    await call();
  }

  /// Every per-event key, so an event never inherits another event's
  /// reference, operation or optional identifiers.
  Map<String, String> _eventKeys({
    String errorId = '',
    String failureKind = '',
    String operation = '',
    String? apiCode,
    String? requestId,
  }) => {
    'error_id': errorId,
    'failure_kind': failureKind,
    'operation': operation,
    'api_code': apiCode ?? '',
    'request_id': requestId ?? '',
  };

  Map<String, String> _identityKeys(CrashIdentity? identity) => {
    'environment': _environment.name,
    'company_id': identity == null ? '' : '${identity.companyId}',
    'pos_config_id': identity == null ? '' : '${identity.posConfigId}',
  };

  /// Writes the event keys, then records the event with the same values
  /// (plus the identity at report time) attached to the event itself.
  Future<void> _record(
    _ReportStep step, {
    required Map<String, String> keys,
    required CrashIdentity? identity,
    required SanitizedReport report,
    required StackTrace stack,
    required String reason,
    bool fatal = false,
  }) async {
    for (final entry in keys.entries) {
      await _call(
        step,
        () => _crashlytics.setCustomKey(entry.key, entry.value),
      );
    }
    final information = [
      for (final entry in {...keys, ..._identityKeys(identity)}.entries)
        '${entry.key}=${entry.value}',
    ];
    await _call(
      step,
      () => _crashlytics.recordError(
        report,
        stack,
        reason: reason,
        information: information,
        fatal: fatal,
      ),
    );
  }

  @override
  void recordFatal(Object error, StackTrace stack) {
    final identity = _identity;
    _enqueue(
      (step) => _record(
        step,
        keys: _eventKeys(),
        identity: identity,
        report: SanitizedReport('Unhandled ${error.runtimeType}'),
        stack: stack,
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
    final identity = _identity;
    final trace = stack ?? StackTrace.current;
    _enqueue(
      (step) => _record(
        step,
        keys: _eventKeys(
          errorId: reference,
          failureKind: failure.kind.name,
          operation: operation,
          apiCode: failure.code,
          requestId: failure.requestId,
        ),
        identity: identity,
        report: SanitizedReport(
          'OrangeFailure(${failure.kind.name}, $operation)',
        ),
        stack: trace,
        reason: failure.kind.name,
      ),
    );
    return reference;
  }

  @override
  void setIdentity(CrashIdentity? identity) {
    _identity = identity;
    _enqueue((step) async {
      for (final entry in _identityKeys(identity).entries) {
        await _call(
          step,
          () => _crashlytics.setCustomKey(entry.key, entry.value),
        );
      }
    });
  }

  @override
  void recordTestNonFatal() {
    final reference = _newReference();
    final identity = _identity;
    final trace = StackTrace.current;
    _enqueue(
      (step) => _record(
        step,
        keys: _eventKeys(errorId: reference),
        identity: identity,
        report: const SanitizedReport('OrangeTest(non-fatal verification)'),
        stack: trace,
        reason: 'verification',
      ),
    );
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
