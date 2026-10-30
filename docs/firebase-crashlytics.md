# Firebase Crashlytics

Crashlytics reports crashes and technical failures of DEV, STG and PROD builds.
Monitoring never interrupts the app: if Firebase is unconfigured, slow (3 s
limit) or failing, the app starts normally with a no-op reporter.

## Architecture

| Piece | Where |
| --- | --- |
| Reporter boundary, no-op reporter, `crashReporterProvider` | `lib/core/monitoring/crash_reporter.dart` |
| Firebase implementation, guarded initialization | `lib/core/monitoring/firebase_crash_reporter.dart` |
| What is worth reporting, operation labels | `lib/core/monitoring/reportable_failure.dart` |
| User-visible Error ID (`OO-XXXXXX`) | `lib/core/monitoring/error_reference.dart` |
| Failure hook | `MobileApiClient.send` (every API failure passes it) |
| Identity from the verified session | `lib/app/providers/crash_identity.dart` |
| Handlers | `bootstrap.dart` (`FlutterError.onError`, `PlatformDispatcher.onError`) |

- **Fatal:** Flutter framework errors and unhandled asynchronous errors are sent
  as fatal. Debug builds never report; release and profile builds of every
  flavor do.
- **Non-fatal:** only technical faults: protocol, backend (5xx), storage and
  configuration are always reported; network and timeout failures are throttled
  to one per operation every 5 minutes. Validation, version conflicts, not found,
  permission denials, expired/used QR codes, rate limits, upgrade-required and
  cancellations are normal business flow and are never reported
  (`reportPolicyFor`, covered by a table test).
- **Error ID:** a reported failure gets a random `OO-XXXXXX` that is appended to
  the message the user sees ("... (Ref: OO-7K3Q9X)") and stored as the
  `error_id` key and log line. The backend `request_id` of the same failure is
  stored too (`request_id`), so the same value can later be searched in Odoo,
  Nginx and Grafana. Failures that are not reported show no ID.
- **Privacy:** Crashlytics receives only a fixed description (error type or
  `OrangeFailure(kind, METHOD /path/{id})`), the stack trace and these keys:
  `environment`, `error_id`, `failure_kind`, `operation`, `api_code`,
  `request_id`, `company_id`, `pos_config_id`. Never exception messages, URLs,
  headers, tokens, QR payloads, barcodes, product or customer data. Path
  segments outside a fixed allowlist become `{id}`.
- **Identity:** `company_id` and `pos_config_id` are the numeric ids of the
  verified session, set after sign-in and cleared at logout, expiry or rejection.
  Whether `company_id` is the customer and `pos_config_id` the shop/POS is a
  backend decision that has **not** been verified, so they are reported under
  their own names. No user, employee or name is sent. Before sign-in only
  `environment` is known.

## Environments and projects

| Flavor | Android app ID | Firebase project |
| --- | --- | --- |
| development | `com.orangeone.app.dev` | non-production |
| staging | `com.orangeone.app.stg` | non-production |
| production | `com.orangeone.app` | production |

All iOS flavors share the App Store bundle ID `ch.orangepos.productscanner`, so on
iOS the flavor's own `GoogleService-Info.plist` (chosen at build time) is the only
separator: one iOS app per Firebase project, registered with that bundle ID. DEV
and STG iOS reports share the non-production project and are told apart by the
`environment` key. `tool/ci/firebase_config.py` refuses a configuration for the
wrong project and requires the two projects to differ.

## Configuration without committed files

`google-services.json` and `GoogleService-Info.plist` are written by CI from
repository **variables** (they are project identifiers that ship in every app, not
credentials) and are gitignored (`android/app/src/*/google-services.json`,
`ios/config/*/GoogleService-Info.plist`):

| Variable | Content |
| --- | --- |
| `FIREBASE_PROJECT_ID_NONPRODUCTION` / `FIREBASE_PROJECT_ID_PRODUCTION` | Firebase project IDs |
| `FIREBASE_IOS_DEVELOPMENT_B64`, `FIREBASE_IOS_STAGING_B64`, `FIREBASE_IOS_PRODUCTION_B64` | base64 of each iOS plist |
| `FIREBASE_ANDROID_PRODUCTION_B64` (and `_DEVELOPMENT_B64`, `_STAGING_B64` if you build those) | base64 of each `google-services.json` |

Secret (protected environments only, never in the archive or allocate jobs):
`FIREBASE_SERVICE_ACCOUNT_JSON`, used solely to upload Dart symbols.

- **Missing configuration fails.** The DEV/STG archive (`archive_flavor.py`), the
  production iOS archive and the production APK write the configuration first and
  verify the finished archive/APK afterwards. Android builds set
  `FIREBASE_CONFIG_REQUIRED=true`, so the Gradle plugins are applied and a
  missing file fails the build. Local and unit-test builds without a
  configuration simply run without Firebase.
- **Android:** `com.google.gms.google-services` and
  `com.google.firebase.crashlytics` are applied only when a configuration exists
  or is required (`android/app/build.gradle.kts`); the R8 mapping uploads with
  the release build.
- **iOS:** Xcode run scripts `[OrangeONE] Firebase Configuration` (copies the
  flavor's plist into the app) and `[OrangeONE] Crashlytics Symbols` (uploads
  dSYMs when `CRASHLYTICS_UPLOAD_SYMBOLS=true`, which workflows set only for real
  deliveries, never for a dry run). The iOS deployment target is **15.0**, which
  Firebase iOS SDK 13 requires; the supported iPhone models are the same as for
  iOS 13.
- **Dart symbols:** release builds use `--split-debug-info`.
  `tool/ci/upload_flutter_symbols.py` uploads them with a pinned `firebase-tools`
  in the protected job; without `FIREBASE_SERVICE_ACCOUNT_JSON` it warns and the
  Flutter stack traces of that build stay unsymbolicated.

## DEV verification

In the **development** flavor the login screen shows a settings gear. Settings has
**Trigger the Crash** (after a confirmation it crashes the app natively) and
**Send test error report** (non-fatal). Reopen the app after the crash so the
report uploads; it appears in the non-production project within minutes. The
route, the gear and the screen exist only when `crashTestControlsProvider` is on,
which the bootstrap enables for the development flavor only. STG and PROD builds
(including TestFlight and customer APKs) have no such route
(`test/app/crash_test_access_test.dart`). Settings is currently only this tool.

## Owner setup (not done by the repository change)

1. Create two Firebase projects (production, non-production); enable Crashlytics.
2. Register Android apps (`com.orangeone.app` in production, `.dev`/`.stg` in
   non-production) and one iOS app per project with bundle ID
   `ch.orangepos.productscanner`; download both configuration files per app.
3. Add the repository variables above (base64: `base64 -w0 file`).
4. Create a service account with the Firebase Crashlytics symbol-upload role and
   add `FIREBASE_SERVICE_ACCOUNT_JSON` to the `ios-development`, `ios-staging`,
   `ios-production` environments (matching project each).
5. Confirm with the backend what `company_id` and `pos_config_id` mean for
   customer and shop, and whether to report more.

Not verified here: Firebase initialization on a device or simulator, report
delivery to the console, symbolication, the Xcode run scripts, the Gradle plugin
versions (`google-services` 4.4.4, `crashlytics` 3.0.6), `--split-debug-info`
with `flutter build ios --config-only`, `firebase-tools` symbol upload, and that
the Crashlytics console can search by the `error_id` key (otherwise use the
BigQuery export or the `error_id=` log line in the report).
