# Firebase Crashlytics

Crashlytics reports crashes and technical failures of DEV, STG and PROD builds.
Monitoring never interrupts the app: if Firebase is unconfigured, slow or
failing, the app starts normally with a no-op reporter. One 3 s limit covers the
whole startup sequence (Firebase initialization and the collection setting); a
sequence that finishes or fails after the limit is ignored and cannot replace
the no-op reporter.

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
  `request_id`, `company_id`, `pos_config_id`. Custom keys are shared by all
  reports, so reports are written one at a time in call order (in the
  background; callers never wait): each event sets `error_id`, `failure_kind`,
  `operation`, `api_code` and `request_id`, empty when absent (fatal errors
  set all five empty; the DEV test report sets only its `error_id`), so no
  event inherits another's values. Never exception messages, URLs,
  headers, tokens, QR payloads, barcodes, product or customer data. Path
  segments outside a fixed allowlist become `{id}`.
- **Identity:** `company_id` and `pos_config_id` are the numeric ids of the
  verified session, set after sign-in and cleared at logout, expiry or rejection.
  Whether `company_id` is the customer and `pos_config_id` the shop/POS is a
  backend decision that has **not** been verified, so they are reported under
  their own names. No user, employee or name is sent. Before sign-in only
  `environment` is known.

## Environments and projects

| Flavor | Built from | GitHub environment | Firebase project |
| --- | --- | --- | --- |
| iOS development | `develop` push (`ios-testflight.yaml`) | `ios-development` | Development |
| iOS staging | `staging` push (`ios-testflight.yaml`) | `ios-staging` | Development (never Production) |
| iOS production | published GitHub Release (`ios-release.yaml`) | `ios-production` | Production |
| Android development | `develop` push (`android-development.yaml`) | `android-development` | Development |
| Android production | published GitHub Release (`android-release.yaml`) | `android-production` | Production |

All iOS flavors share the App Store bundle ID `ch.orangepos.productscanner`, so on
iOS the configuration file that CI selects per environment is the only separator:
one iOS app per Firebase project, registered with that bundle ID. Android apps are
distinguished by application ID (`com.orangeone.app`, `.dev`, `.stg`). DEV and STG
iOS reports share the Development project and are told apart by the `environment`
key.

## Configuration without committed files

`google-services.json` and `GoogleService-Info.plist` are never committed
(gitignored: `android/app/src/*/google-services.json`,
`ios/config/*/GoogleService-Info.plist`). Every GitHub environment holds the
**client configuration** of its own project under the **same names**; CI writes the
files for the build and verifies the finished app.

- **Client configuration** (Firebase project identifiers and the public client API
  key; they ship inside every app, so they are *Variables*, not Secrets).
- **Service account** (a private credential; a *Secret*, used only to upload Dart
  symbols, only in protected signing jobs).

How it flows (iOS): the `allocate` job already runs in the protected environment.
It validates `FIREBASE_CONFIG_BASE64` (`firebase_config.py export`) and passes it as
a job output to the credential-free `archive` job, which therefore never reads an
environment or a secret. Android jobs run in their own environment and read the
variables directly.

- **Wrong project fails before distribution.** `firebase_config.py` requires the
  `production` flavor to use `FIREBASE_PRODUCTION_PROJECT_ID` and the `development`
  and `staging` flavors to use a different project. It also checks the iOS bundle ID
  (`ch.orangepos.productscanner`) and the Android application ID of the flavor, and
  verifies the finished archive/APK again.
- **Missing configuration fails.** The DEV/STG archive (`archive_flavor.py`), the
  production iOS archive, and both Android workflows write the configuration first.
  Android builds set `FIREBASE_CONFIG_REQUIRED=true`, so the Gradle plugins are
  applied and a missing file fails the build. Local and unit-test builds without a
  configuration run without Firebase.
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
- **Reporting from debug builds:** staging and production report only from
  release/profile builds; the development flavor also reports from debug builds
  (it uses the Development project), which is what the debug-signed Android
  development APK needs.

## DEV verification

In the **development** flavor the login screen shows a settings gear. Settings has
**Trigger the Crash** (after a confirmation it crashes the app natively) and
**Send test error report** (non-fatal). Reopen the app after the crash so the
report uploads; it appears in the non-production project within minutes. The
route, the gear and the screen exist only when `crashTestControlsProvider` is on,
which the bootstrap enables for the development flavor only. STG and PROD builds
(including TestFlight and customer APKs) have no such route
(`test/app/crash_test_access_test.dart`). Settings is currently only this tool.

## GitHub setup guide (owner, manual)

Names are identical in every environment. Values come from the Firebase console of
the project named in the table; nothing here is invented or stored in Git.

### Client configuration (Variables, not secret)

| Name | Type | Where to add it | Firebase project | Value from | Used by | Base64 |
| --- | --- | --- | --- | --- | --- | --- |
| `FIREBASE_CONFIG_BASE64` | Variable | `ios-development` | Development, iOS app | Firebase console > Project settings > Your apps > iOS app `ch.orangepos.productscanner` > download `GoogleService-Info.plist` | `ios-testflight.yaml` (develop) | **Yes**: `base64 -w0 GoogleService-Info.plist` (macOS: `base64 -i GoogleService-Info.plist | tr -d '\n'`) |
| `FIREBASE_CONFIG_BASE64` | Variable | `ios-staging` | Development, iOS app (same file as `ios-development`) | same | `ios-testflight.yaml` (staging) | Yes |
| `FIREBASE_CONFIG_BASE64` | Variable | `ios-production` | Production, iOS app | Production project > Your apps > iOS app `ch.orangepos.productscanner` > `GoogleService-Info.plist` | `ios-release.yaml`, `ios.yaml` | Yes |
| `FIREBASE_CONFIG_BASE64` | Variable | `android-development` | Development, Android app `com.orangeone.app.dev` | Development project > Your apps > Android app > download `google-services.json` | `android-development.yaml` | Yes: `base64 -w0 google-services.json` |
| `FIREBASE_CONFIG_BASE64` | Variable | `android-production` | Production, Android app `com.orangeone.app` | Production project > Your apps > Android app > `google-services.json` | `android-release.yaml` | Yes |
| `FIREBASE_PROJECT_ID` | Variable | each of the five environments above | the environment's own project | Project settings > General > Project ID (also `project_id` inside the file) | all of the above (cross-check) | No |
| `FIREBASE_PRODUCTION_PROJECT_ID` | Variable | **Repository** variables (Settings > Secrets and variables > Actions > Variables) | Production | Production project > Project settings > Project ID | all of the above (guard: production must equal it, development and staging must differ) | No |

Staging has no Firebase project of its own: `ios-staging` uses the **Development**
project. Do not put Production values in `ios-staging`; the workflow fails if you do.

### Private service-account credential (Secret)

| Name | Type | Where to add it | Firebase project | Value from | Used by | Base64 |
| --- | --- | --- | --- | --- | --- | --- |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | **Secret** | `ios-development`, `ios-staging` | Development | Google Cloud console > IAM > Service accounts of the Development project: create a JSON key for an account with the **Firebase Crashlytics Symbol Uploader** role | `ios-testflight.yaml` (Dart symbol upload, real deliveries only) | No: paste the JSON as is |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | **Secret** | `ios-production`, `android-production` | Production | same, in the Production project | `ios-release.yaml`, `android-release.yaml` | No |

It is optional: without it a build only warns and its Flutter stack traces stay
unsymbolicated. It is never given to `android-development`, to build jobs without
an environment, or to Android jobs of another project.

### Environments to create or adjust

| Environment | Action | Branch / tag restriction |
| --- | --- | --- |
| `ios-development`, `ios-staging`, `ios-production` | Exist; **add only** the variables above. Keep the Apple signing secrets untouched. | existing (`develop`, `staging`, `main` plus `v*` tags for production) |
| `android-development` | **Create** | deployment branch: `develop` only |
| `android-production` | **Create**; copy the Android keystore secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD`, `ANDROID_SIGNING_CERT_SHA256`) from the old `android-release` environment if it exists; the workflow no longer uses that name | tags `v*`; keep required reviewers |

`ios-production` must allow the release tags `v*` (it allowed `main` before).

### Other setup

1. Create the two Firebase projects with Crashlytics enabled; register the apps
   with the IDs above.
2. Confirm with the backend what `company_id` and `pos_config_id` mean for
   customer and shop, and whether to report more.

Not verified here: Firebase initialization on a device or simulator, report
delivery to the console, symbolication, the Xcode run scripts, the Gradle plugin
versions (`google-services` 4.4.4, `crashlytics` 3.0.6), `--split-debug-info`
with `flutter build ios --config-only`, `firebase-tools` symbol upload, the job
output hand-over on a hosted runner, and that the Crashlytics console can search by
the `error_id` key (otherwise use the BigQuery export or the `error_id=` log line).
