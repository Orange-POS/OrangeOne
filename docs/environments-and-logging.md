# Application environments and logging (Task 11)

Each native flavor has a matching Dart entry point: development, staging and
production. Bootstrap checks the native flavor before starting authentication.
Settings are parsed once, validated, and injected with Riverpod. Incorrect builds
or invalid settings show a safe configuration-error screen before session restore
or network requests. No supplied values are echoed in errors.

## Build settings

Copy the matching `config/<flavor>.example.json` to an ignored
`config/<flavor>.local.json`, edit nonsecret values and pass it explicitly:

```powershell
flutter run --flavor development --target lib/main_development.dart --dart-define-from-file=config/development.local.json
flutter run --flavor staging --target lib/main_staging.dart --dart-define-from-file=config/staging.local.json
flutter build apk --release --flavor production --target lib/main_production.dart --dart-define-from-file=config/production.local.json
```

Flutter does not automatically select JSON files. The native flavor and entry
point choose the environment; `APP_ENVIRONMENT`, when supplied, must match them.
The templates include this marker to catch accidental cross-environment files.
Omitting the file preserves valid QR-discovery defaults.

| Setting | Default / validation |
| --- | --- |
| `APP_ENVIRONMENT` | Optional; when supplied, exact native/entry-point environment name required |
| `ODOO_BASE_URL` | Optional fallback origin; omit for QR discovery. If supplied, nonempty HTTP(S) origin only, no credentials, path, query or fragment |
| `ODOO_CONNECT_TIMEOUT_MS` | 15000; integer from 1 to 600000; also used for sending |
| `ODOO_RESPONSE_TIMEOUT_MS` | 20000; integer from 1 to 600000 |
| `APP_DEBUG_LOGGING` | `true` in development debug, otherwise `false`; accepts only `true` or `false` |

Missing required native flavor and mismatched environment markers are rejected.
Malformed/empty explicit settings are rejected rather than silently defaulted.
No compile-time backend URL is required by the confirmed QR authentication flow:
QR and saved sessions select their validated POS origin per request. The optional
base URL supplies a fallback for requests without an explicit origin; it does not
pin or override QR hosts. This preserves deployments with different POS machines.
HTTP support remains compatible with existing LAN POS installations. Prefer HTTPS.
No business feature needs changing to configure these settings.

Dart defines are compiled into the app and are **not secret storage**. Never put
credentials, tokens, QR challenges, database secrets or customer data in JSON or
Dart defines. Local files are ignored; checked-in examples contain no real hosts.

## Structured logging and diagnostics

`core/logging/app_logger.dart` provides an injectable logger and sink using
`dart:developer` with JSON records. Debug logging is available in development;
staging debug can explicitly opt in. Production flavor and all profile/release
builds disable the sink regardless of the logging flag. Development diagnostics
are registered only in development debug builds; direct links in other builds
reach the normal not-found screen. The diagnostics switch defaults closed when
bootstrap has not configured it.

Records use a fixed enum vocabulary for startup, framework/platform failure and
RPC start/success/failure. Approved fields are UTC timestamp, environment, event,
local sequential request ID, elapsed milliseconds and typed failure kind.
Application-level `ok: false` is a failure, independent of transport/protocol errors.
Request IDs are local counters, never session identifiers.

The logger accepts no free-text message, exception, stack, payload, response,
header, URL, QR content or product/customer data. Those fields cannot accidentally
reach the sink. Framework/platform error handlers emit fixed safe events rather
than dumping raw exception details. This intentionally sacrifices raw error
messages/stacks; debugger breakpoints remain available during development.
There is no persistent logging, remote telemetry or automatic retry. Production
Crashlytics/telemetry remains a separate task. OS/plugin diagnostics are outside
this Dart logger; verify native release logs during release qualification.

## Verification

Focused tests cover all environment/build-mode policies, malformed/missing
settings, flavor mismatch, route availability, safe startup UI and RPC records
with secret sentinel values in headers, payloads, responses and exceptions.
Run `flutter analyze --fatal-infos --fatal-warnings` and `flutter test`.
Native iOS compilation requires macOS; these tests do not certify live Odoo,
CI execution or store-release logging behavior.

Validation on 2026-10-19: static analysis passed with no issues; all 341 Flutter
tests passed. Android arm64 debug APK builds passed for development, staging and
production using each flavor's matching example JSON and entry point. No live
Odoo calls, inventory writes, phone installation, signed release or iOS builds
were performed for Task 11.
