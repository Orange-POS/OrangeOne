# QR authentication and session contract

## Scope

Task 04 implements POS QR login, secure local sessions and guarded navigation.
It does not implement inventory actions or product-barcode scanning. `/home` is a
minimal signed-in destination with sign-out, not a completed inventory dashboard.
The earlier initialization page remains at `/diagnostics/initialization`.

## Backend contract (Mobile API v2)

Login and sessions follow the OrangeONE Mobile API v2 (`openapi.yaml` of the
`mupi_mobile_auth` addon, Orange-POS/odoo_addons PR #192); see
[Mobile API v2 integration](mobile-api-v2.md). The legacy JSON-RPC challenge and
token-check routes are no longer used.

1. An authenticated POS user creates a challenge in the Odoo POS UI
   (`POST /auth/qr-challenges`, web session). The app never calls that route.
2. The POS QR is a JSON object with `v: 2`, `type`, `challenge_id`, `nonce`,
   `pos_config_id`, `api_base` and UTC `expires_at`. Payloads without `v` that
   look like the old format are reported as outdated QR codes; other versions or
   types are rejected.
3. The client rejects empty/oversized (>8192 characters), malformed, expired or
   untrusted `api_base` payloads before any request. IDs must be positive
   integers; timestamps must be real, timezone-qualified dates.
4. `POST {api_base}/auth/qr-exchange` sends `challenge_id`, `nonce`,
   `pos_config_id` and the device (random install id, platform, app version).
   The QR is single use and the server consumes it.
5. The grant contains an opaque access token (`oa_…`, about 15 minutes), a
   rotating refresh token (`or_…`), the session family expiry and the user,
   company, POS config and session identifiers. The returned POS config must
   match the scanned QR. Models map snake_case fields to the domain `AuthSession`.
6. `POST /auth/token/refresh` rotates the refresh token (single flight, refreshed
   30 seconds before expiry or once after `TOKEN_EXPIRED`); a different identity
   in the rotated grant ends the session. `POST /auth/logout` revokes the token
   family.

The server remains authoritative for QR expiry, nonce validity, single-use
consumption, token validity, revocation and permissions. QR payloads, tokens and
session identifiers are never logged or stored outside secure storage.

## Configuration and origin trust

The POS QR supplies the server origin, including its port. No fixed IP or app
rebuild is required when switching POS servers. Scan only QR codes from your
trusted POS: URL validation does not verify the server operator's identity.
Copy `config/odoo.example.json` to an ignored local file to customize timeouts:

```sh
flutter run --flavor development --target lib/main_development.dart --dart-define-from-file=config/development.local.json -d DEVICE_ID
flutter run --flavor staging --target lib/main_staging.dart --dart-define-from-file=config/staging.local.json
flutter build ios --release --no-codesign --flavor production --target lib/main_production.dart --dart-define-from-file=config/production.local.json
```

Supported nonsecret defines:

| Key | Meaning |
| --- | --- |
| `ODOO_BASE_URL` | Optional fallback origin for non-auth API calls; QR login and saved sessions use their own validated origin |
| `ODOO_CONNECT_TIMEOUT_MS` | Connect/send timeout, default 15000 ms |
| `ODOO_RESPONSE_TIMEOUT_MS` | Receive timeout, default 20000 ms |

Timeouts must be between 1 and 600000 milliseconds. Defines are compiled into the
application and are not secret storage. Never put tokens, QR challenges, passwords
or private keys in configuration files. QR login does not require ODOO_BASE_URL.

All three flavors support HTTP and HTTPS for scanned POS
servers. Each origin must have a valid host and port and no credentials, path,
query or fragment. The QR endpoint must exactly match that origin plus the fixed
validation path. Redirects are disabled and TLS validation is never bypassed.
Requests carry their own origin; a saved token is checked only against the origin
saved with it in secure storage. Changing a build-time fallback cannot redirect
that token to another server. HTTP is unencrypted; prefer HTTPS on deployed networks.
Android's shared manifest permits cleartext traffic for every flavor. Both iOS
Info plists permit arbitrary loads because QR origins are selected at runtime;
this ATS exception needs justification during App Store submission. HTTPS
certificate validation remains enabled.

All requests use the session's `api_base`; the app does not invent a database
selection field or substitute generic Odoo APIs.

## Secure storage and lifetime

`SecretStore` is an injectable core abstraction. Its platform implementation uses
`flutter_secure_storage`, with flavor-separated keys of the form
`orangeone.<flavor>.session.v2` (a leftover v1 record is deleted on restore) and
`orangeone.<flavor>.install_id`. Tokens and required session metadata are stored
as one secure record only after backend success and schema validation. Normal
preferences, files and logs contain no authentication secrets. Session/challenge
`toString()` implementations are redacted.

Android backup is disabled for the application. iOS uses device-only, unlocked
Keychain accessibility and flavor-specific application Keychain groups. The
entitlement is configured for all nine Runner flavor/build configurations; signed
iOS device validation still requires Apple signing assets.

On a full application restart, the repository reads secure storage and validates
an existing session once through `GET /auth/session` (refreshing the access token
first when needed). Validation has
a 15-second deadline. Invalid, rejected, unreachable or timed-out validation
deletes the secure record and returns to fresh QR login after successful cleanup.
The pending request is cancelled at the deadline; late responses cannot restore
an old session or delete a newer session. There are no automatic restore retries.
Cleanup waits at most 2 additional seconds (17 seconds maximum when validation
uses its entire budget). Stalled deletion surfaces a safe storage error, never a
successful logout. New login is blocked while the actual platform deletion remains
pending; writes/deletes stay ordered so a late deletion cannot erase a new login.

A successful QR login stays in secure storage across process restarts until local
logout or backend expiry/rejection. Ordinary background /
foreground transitions do not revalidate or poll. The server's session family
expiry still applies; refresh rotation cannot extend it.

Task 13 permits read-only cached access during a network outage inside an already
verified, unexpired session. Transient product network/timeout failures no longer
sign out this session; they disable writes and expose only approved cached data.
Cache misses remain network errors. Startup validation remains strict, and backend
session rejection, expiry and logout still reset session-dependent state. No
periodic ping or write replay is introduced. See [Offline reads](offline-data.md).

Home exposes a visible **Logout** action. Expiry and logout hide protected UI and
clear local secure storage. Logout clears local state first and then calls
`POST /auth/logout` (best effort) to revoke the token family. A new session
requires a fresh POS QR code.

Login is guarded against concurrent scans in both the scanner/controller and
repository. Sign-out cancels a pending login; generation checks ignore stale
results. Secure writes/deletes are serialized so a late login write cannot
recreate a session after logout. Storage failures are surfaced and never count as
successful sign-in or successful secret deletion.

## Camera and UI

The login/QR screens use the inspected Figma nodes `353:3890` and `353:3910`, the
attached references, local Inter font, matching Lucide SVG glyphs, and the Figma
camera indicator. Static exports are not used as screen-sized images. Layout uses
safe areas, bounded responsive sizes and scrolling for short screens. Camera
permission messages and authentication errors extend the static reference with
accessible actions. No product/barcode screen from the reference was implemented.

Figma returned both initial screens/screenshots before the Starter-plan MCP call
limit prevented further inspection. The authenticated home design was not supplied
or independently inspected, so it intentionally remains minimal.

The login screen has a language selector (six languages, remembered across
restarts) and the QR scanner only runs on Wi-Fi: see
[localization](localization.md). Without Wi-Fi the camera is not started and the
screen asks the user to connect to the POS machine's Wi-Fi network; the app
cannot verify which network that is.

The native scanner is QR-only, uses the rear camera and stops after accepting a
code. It is stopped/disposed on route removal and paused in the background.
Permission denial offers a retry; permanent denial offers Settings; restrictions
display an explanation. The scanner reports actual camera/loading/error status.
Authentication errors keep scanning paused until the user chooses a new scan.
No automatic replay is attempted: a timeout might mean a single-use challenge was
already consumed, so generate a new POS QR after an interrupted login.

Android declares camera/Internet permissions. iOS declares camera and local-network
usage descriptions. Only the development iOS plist enables local networking for
the supplied LAN server; staging/production use the strict common plist. The
permission plugin's Swift package detects the camera usage description. If a
future migration switches to CocoaPods, enable its camera permission macro too.

## Navigation

`app/router/auth_redirect.dart` owns the pure redirect policy; the router listens
to session changes without recreating GoRouter on every authentication event.

| Route name | Path | Behavior |
| --- | --- | --- |
| `login` | `/login` | Public login; signed-in users go home |
| `qrLogin` | `/login/scan` | Nested scanner, opened with push; back returns `false` |
| `home` | `/home` | Protected, reached only with a verified current session |
| `startup` | `/startup` | Neutral loading while a protected-route session is checked |
| `initialization` | `/diagnostics/initialization` | Existing local configuration diagnostic |

Login supports a sanitized `reason=expired` query parameter for a fixed informational
message; arbitrary query text is never rendered or used for authorization. Login
success is communicated through session state and redirects to home. Unknown URLs
render a safe not-found fallback with a named navigation action. Inventory entity
routes and extra navigation shells are deferred until required.

## Verification

Session-policy update (2026-10-17): all 284 Flutter tests passed and strict
`flutter analyze --fatal-infos --fatal-warnings` passed. Coverage includes the
15-second cancellation deadline and late response, first offline failure without
retry, clearing saved secrets, visible Home logout, and no resume revalidation.
The development APK also built successfully, and the controlled integration
journey passed on a Samsung SM-A315F (login, scanning, price update, product edit,
and visible Logout). These checks use controlled backends; a live POS outage and
secure-storage behavior against a real POS login still require manual verification.
After the device test, the normal development APK was reinstalled successfully,
launched, and confirmed running as the foreground activity on the phone.

Unit/provider/widget tests use controlled Dio responses, an in-memory SecretStore,
fake repositories, injected clocks and fake camera input. They cover protocol and
business failures, QR/response mapping, storage/restore/logout races, session expiry,
permissions, navigation, query parameters/results, first-frame sizing and phone
sizes. No test contacts production Odoo or requires a camera.

`integration_test/app_test.dart` runs a controlled login → scanner → home → logout
journey for the native flavor, with fake authentication/camera providers. CI already
runs this on Android emulators for all three flavors. This test does not prove live
camera recognition, Keychain/Keystore persistence or deployed Odoo compatibility.
Those require a physical device and a fresh POS-generated QR challenge.

See [Task 04 verification](task04-validation.md) for executed checks and remaining
platform/deployment verification.

References: [Mobile API v2 integration](mobile-api-v2.md),
[mobile_scanner](https://pub.dev/packages/mobile_scanner),
[secure storage platform setup](https://pub.dev/packages/flutter_secure_storage),
[Apple local-network ATS behavior](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).




