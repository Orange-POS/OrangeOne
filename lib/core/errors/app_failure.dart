enum FailureKind {
  configuration,
  validation,
  conflict,
  expiredQr,
  usedQr,
  unsupportedQr,
  network,
  timeout,
  protocol,
  backend,
  unauthenticated,
  forbidden,
  storage,
  cancelled,
  notFound,
  rateLimited,
  upgradeRequired,
}

/// Field-level validation reported by the Mobile API (`error.details`).
class AppFieldError {
  const new(this.field, this.code, {this.message});

  /// Dotted body path; empty for a rule about the whole record
  /// (`BUSINESS_RULE_VIOLATION` details without a field).
  final String field;

  /// Machine code such as `REQUIRED` or `INVALID_DECIMAL`.
  final String code;

  /// The server's localised, display-safe text, when short enough; shown
  /// only for codes the app has no own text for.
  final String? message;
}

/// Safe application failure. Never retains a response, token or QR payload.
class AppFailure implements Exception {
  const new(
    this.kind,
    this.message, {
    this.code,
    this.fieldErrors = const [],
    this.retryable = false,
    this.retryAfter,
    this.requestId,
    this.errorReference,
  });

  final FailureKind kind;
  final String message;

  /// Mobile API error code (for example `VERSION_CONFLICT`), when known.
  final String? code;
  final List<AppFieldError> fieldErrors;
  final bool retryable;
  final Duration? retryAfter;

  /// Server request id for support correlation; not a secret.
  final String? requestId;

  /// User-visible `OO-XXXXXX` reference when this failure was reported to
  /// monitoring; support finds the report with it.
  final String? errorReference;

  /// The same failure with a reference appended to the message the user sees.
  AppFailure withReference(String reference) => AppFailure(
    kind,
    '$message (Ref: $reference)',
    code: code,
    fieldErrors: fieldErrors,
    retryable: retryable,
    retryAfter: retryAfter,
    requestId: requestId,
    errorReference: reference,
  );

  @override
  String toString() => 'AppFailure(${kind.name})';

  /// Kinds where the server answered and refused the write: nothing was
  /// saved, so the outcome is certain (never "could not be confirmed").
  static const Set<FailureKind> writeRefusals = {
    FailureKind.forbidden,
    FailureKind.validation,
    FailureKind.unauthenticated,
    FailureKind.conflict,
    FailureKind.notFound,
    FailureKind.rateLimited,
  };

  /// Whether [error] is one of the [writeRefusals].
  static bool refusedWrite(Object error) =>
      error is AppFailure && writeRefusals.contains(error.kind);
}

/// The text to show for [error]: an [AppFailure]'s display-safe message, a
/// [FormatException]'s message (a reply the app could not read), otherwise
/// [fallback].
String failureText(Object? error, String fallback) => switch (error) {
  AppFailure(:final message) => message,
  FormatException(:final message) => message,
  _ => fallback,
};

const invalidQr = AppFailure(
  FailureKind.validation,
  'This is not a valid OrangeONE login QR code.',
);
const invalidSession = AppFailure(
  FailureKind.unauthenticated,
  'Your session is no longer valid. Sign in with a new POS QR code.',
);
const invalidResponse = AppFailure(
  FailureKind.protocol,
  'The server returned an unexpected response. Contact your administrator.',
);
const storageFailure = AppFailure(
  FailureKind.storage,
  'Secure session storage is unavailable. Unlock your device and try again.',
);
const cancelledOperation = AppFailure(
  FailureKind.cancelled,
  'Sign-in was cancelled. Scan a new POS QR code to continue.',
);
