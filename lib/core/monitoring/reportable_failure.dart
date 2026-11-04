import 'package:orange_one/core/errors/app_failure.dart';

/// Which failures are technical faults worth a Crashlytics non-fatal report.
///
/// Expected outcomes (validation, version conflicts, missing products,
/// permission denials, expired or used QR codes, rate limits, cancellation)
/// are normal business flow and never reported. Unreachable-server failures
/// are reported, but throttled, because a shop that is offline would
/// otherwise create one report per tap.
enum ReportPolicy { never, always, throttled }

ReportPolicy reportPolicyFor(FailureKind kind) => switch (kind) {
  FailureKind.protocol ||
  FailureKind.backend ||
  FailureKind.storage ||
  FailureKind.configuration => ReportPolicy.always,
  FailureKind.network || FailureKind.timeout => ReportPolicy.throttled,
  FailureKind.validation ||
  FailureKind.conflict ||
  FailureKind.expiredQr ||
  FailureKind.usedQr ||
  FailureKind.unsupportedQr ||
  FailureKind.unauthenticated ||
  FailureKind.forbidden ||
  FailureKind.cancelled ||
  FailureKind.notFound ||
  FailureKind.rateLimited ||
  FailureKind.upgradeRequired => ReportPolicy.never,
};

/// A stable operation label such as `POST /products/{id}/stock-adjustments`.
///
/// Only fixed Mobile API path words survive. Every other segment (a product
/// id, a barcode, a token) becomes `{id}`, so no data can leak through the
/// path and reports of one endpoint group together.
String operationLabel(String method, String path) {
  const words = {
    'auth',
    'qr-exchange',
    'token',
    'refresh',
    'session',
    'logout',
    'products',
    'by-barcode',
    'barcode',
    'changes',
    'stock-adjustments',
    'stock-movements',
    'categories',
    'taxes',
    'price',
  };
  final pathOnly = path.split('?').first;
  final segments = pathOnly
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => words.contains(segment) ? segment : '{id}')
      .join('/');
  return '${method.toUpperCase()} /$segments';
}
