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
}

/// Safe application failure. Never retains a response, token or QR payload.
class AppFailure implements Exception {
  const new(this.kind, this.message);

  final FailureKind kind;
  final String message;

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
