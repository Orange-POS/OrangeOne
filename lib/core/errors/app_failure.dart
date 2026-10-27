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
  const new(this.field, this.code);

  final String field;

  /// Machine code such as `REQUIRED` or `INVALID_DECIMAL`.
  final String code;
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

  @override
  String toString() => 'AppFailure(${kind.name})';
}

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
