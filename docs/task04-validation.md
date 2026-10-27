# Task 04 verification — 2026-10-16

> Historical record. The JSON-RPC routes it describes were replaced by the
> Mobile API v2; see [Mobile API v2 integration](mobile-api-v2.md).


## Implemented

- Feature-first authentication domain contracts/entities/use case, data sources,
  QR/session mapping, repository and Riverpod composition.
- Login and QR-scanner UI based on the two inspected Figma nodes and supplied
  references, local Inter/Lucide assets and shared branding. The home destination
  is intentionally minimal; product barcode scanning/dashboard work is deferred.
- Pinned-origin configuration, shared Dio, configurable timeouts, JSON-RPC request
  IDs/envelope checks, distinct transport/protocol/business failures and safe errors.
- Secure platform storage abstraction, startup server token validation, expiry,
  resume revalidation, logout and stale-login/write-race protection.
- QR-only camera with denied/permanent/restricted permission states and lifecycle
  handling. No raw QR values or token bodies are logged or persisted in source.
- Named/nested routes, protected home, sanitized query handling, push/pop results,
  not-found fallback and the retained initialization diagnostic.

## Checks executed

- Formatting check: passed (50 Dart files).
- `flutter analyze --fatal-infos --fatal-warnings`: passed, no issues.
- `flutter test --coverage`: passed, 124 unit/provider/widget tests.
- Non-default timeout check: tests run with `ODOO_CONNECT_TIMEOUT_MS=12345` and
  `ODOO_RESPONSE_TIMEOUT_MS=23456` passed, confirming defines are honored.
- Development Android APK build: passed using the supplied development origin.
- Development app installed/launched on the connected SM A315F; scanner semantics
  reported `Camera on · Looking for QR code…`, confirming permission and preview
  startup on that device. Source hot reload also completed successfully.
- Finalized arm64 APK was installed and launched cleanly after reconnecting Wi-Fi
  debugging. On-screen Back returned from scanner to login. A QR-free landing
  screenshot was captured and visually inspected at `build/orangeone-login.png`.
- The device's initial zero-size frame exposed a layout issue; a zero-size guard
  and regression test were added. Adding a widget constructor field during live
  reload required a clean application restart; it is not a release runtime path.
- iOS plist/entitlement XML parsed successfully; all nine Runner flavor/build
  configurations reference Keychain entitlements, and only the three development
  Runner configurations use the development local-network plist.
- Local development configuration is ignored by Git. Dependencies resolved with
  permission_handler 12.0.1, compatible with the project's Android SDK 36;
  the newer major version requires SDK 37 and was not retained.

## Test boundaries and remaining verification

- Tests use controlled HTTP responses, in-memory storage, fake camera/repository
  dependencies and injected time. No test sends authentication/inventory requests
  to production Odoo or relies on a physical camera.
- The native integration test now covers the controlled login/scan/home/logout
  journey. It is configured for the existing CI flavor matrix; it has not been
  executed on GitHub in this workspace (no remote configured).
- A successful login, secure token write/restart restoration and logout against
  the deployed Odoo server still need a fresh POS-generated QR. The supplied
  sample was expired and was never replayed against the backend.
- Odoo runtime tests were not run: no Odoo test server/database was provisioned.
  The provided controller/model/test sources were used as the contract reference.
- iOS compilation/device permission and Keychain flows were not executed on this
  Windows host. Use the configured macOS unsigned-build workflow; signed device
  verification needs the Apple development setup.
- Figma returned initial login/scanner context/screenshots, then reached the
  Starter-plan MCP call limit. Additional design metadata/home design were not
  verified. No pixel-perfect/full-dashboard fidelity is claimed.
- The existing supported Gradle/AGP versions still emit future-support warnings;
  no build-validation bypass was added. A Gradle/AGP major migration is separate.

See [authentication setup and contract](authentication.md) for run commands,
trust policy, secure-storage details and deployment prerequisites.

## Dynamic POS server correction — 2026-10-16

The QR schema was unchanged; authentication incorrectly pinned its origin to a
build-time address. QR parsing now validates the scanned backend origin and its
matching fixed login endpoint. Requests use that origin explicitly. Secure
sessions retain it, and restoration checks the token only against its saved server.
Switching POS servers does not copy bearer headers to the next login request.

Per the user's explicit requirement, development, staging and production accept
HTTP and HTTPS. The shared Android manifest permits cleartext; both iOS Info plists
carry the runtime-origin ATS exception. Redirects remain disabled, HTTPS certificate
validation remains enabled, and invalid endpoint/origin/expiry data is rejected.

Verification: formatting passed, Flutter analysis reported no issues, and all 136
unit/provider/widget tests passed. Coverage includes changing IPs and ports,
all-flavor transport policies, origin-bound restoration, switching servers without
token leakage, and malformed QR origins/endpoints. Native XML parsed successfully.
The Android development APK built successfully. iOS and staging/production binaries
were not built locally; live Odoo authentication requires a fresh POS QR code.

The final development APK was installed and launched on the connected SM A315F
(192.168.1.5:42371); the Flutter live preview remains connected. This verifies
deployment/startup, not a real Odoo login or physical QR authentication.

