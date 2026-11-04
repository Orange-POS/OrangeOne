import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';

/// Verified, non-personal identity of the signed-in POS session, attached to
/// reports so support can find an incident. Values are numeric Odoo ids from
/// the authenticated session; no tokens, names, e-mail or QR data.
class CrashIdentity {
  const new({required this.companyId, required this.posConfigId});

  final int companyId;
  final int posConfigId;
}

/// Reporting boundary of the application. Implementations must never throw:
/// monitoring may not interrupt the app.
abstract interface class CrashReporter {
  /// Flutter framework or unhandled asynchronous error.
  void recordFatal(Object error, StackTrace stack);

  /// A technical failure that the app handled. Returns the user-visible
  /// reference when a report was sent, otherwise null.
  String? recordFailure(
    AppFailure failure, {
    required String operation,
    StackTrace? stack,
  });

  /// Sets the identity after sign-in and clears it (`null`) on sign-out.
  void setIdentity(CrashIdentity? identity);

  /// DEV verification only: reports a non-fatal test error.
  void recordTestNonFatal();

  /// DEV verification only: crashes the app natively.
  void triggerTestCrash();
}

/// Used when Firebase is unavailable, unconfigured or disabled.
class NoopCrashReporter implements CrashReporter {
  const new();

  @override
  void recordFatal(Object error, StackTrace stack) {}

  @override
  String? recordFailure(
    AppFailure failure, {
    required String operation,
    StackTrace? stack,
  }) => null;

  @override
  void setIdentity(CrashIdentity? identity) {}

  @override
  void recordTestNonFatal() {}

  @override
  void triggerTestCrash() {}
}

final crashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
  name: 'crashReporterProvider',
);
