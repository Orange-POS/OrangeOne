# Android and iOS deployment

## Pipeline

| Workflow | Trigger | Output |
| --- | --- | --- |
| Flutter Tests | Every push/PR and manual | Offline tests, analysis, formatting, coverage |
| Android APK | Every push, PR targeting main, manual | Production-flavor debug-signed APK |
| iOS Unsigned | Every push, PR targeting main, manual | Production unsigned app ZIP on macOS 26 |
| iOS TestFlight | Successful Flutter Tests for a main push; manual retry from main | Signed production IPA and internal TestFlight upload |

Merge approved changes into main. The successful main-push test run triggers
TestFlight automatically, pinned to that tested SHA. Failed/cancelled tests, forks
and PR test runs cannot sign. Signing runs are serialized and not cancelled by
new pushes. The manual action accepts main only and reruns quality gates. To
retry a failed upload, use Run workflow from main; use a new main commit if source
changes. The workflow files must be merged into main before these triggers work.

There is one production Apple app ID: `com.orangeone.app`. The production scheme,
`lib/main_production.dart` and `config/production.example.json` are used together.
The marketing version comes from `pubspec.yaml`. Fastlane queries App Store
Connect and increments the existing integer TestFlight build number for that
version, up to 9999. Use a new marketing version before exceeding that limit.
Coordinate any uploads from other systems to avoid simultaneous build-number
allocation. No staging/development Apple IDs are required.

## Seven GitHub repository secrets

Use Settings > Secrets and variables > Actions with these exact names:

| Name | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `IOS_CERTIFICATE_BASE64` | Base64 `.p12` Apple Distribution certificate including private key |
| `IOS_CERTIFICATE_PASSWORD` | Password used to export that `.p12` |
| `IOS_PROVISION_PROFILE_BASE64` | Base64 App Store distribution `.mobileprovision` |
| `APP_STORE_CONNECT_KEY_BASE64` | Base64 App Store Connect API `.p8` private key |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID |

Create the app record in App Store Connect first. The certificate/profile must
belong to the supplied team and exact production app ID and include current
capabilities. Development/ad-hoc/expired profiles are rejected. Accept Apple's
agreements and grant the API key app access and an appropriate upload/build
metadata role. A public certificate without its private key cannot sign.

Generate base64 on a trusted machine, copy to GitHub secrets, then clear the
clipboard. For example on Windows:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\distribution.p12')) | Set-Clipboard
```

Repeat for the profile and `.p8`. Never commit these files, their values, private
keys or passwords. No additional environment names or keychain-password secret
is needed. Temporary passwords are random per run.

## Signing and TestFlight

The GitHub-hosted macOS runner uses locked Fastlane dependencies, installs the
certificate into a temporary keychain, validates/installs the profile and builds
the production IPA using manual signing. Only the signing step receives Apple
secrets. Fastlane restores the keychain list and deletes the temporary profile,
keychain and private files in ensure blocks, including on failure. Runner
destruction covers abrupt termination; do not reuse this on persistent runners.
Do not enable shell tracing, dump environment variables or upload signing logs.

The beta lane uploads the IPA through an App Store Connect API key and waits for
processing. It never submits for App Store review or releases publicly. In App
Store Connect, assign the processed build to an internal tester group. Testers
install with Apple's TestFlight app. External testers need separate beta review
and group configuration, not automated here. Resolve export compliance prompts
truthfully; the pipeline does not invent exemption answers.

The signed IPA artifact is retained for seven days. Unsigned iOS ZIPs cannot be
installed on a physical iPhone. Android artifacts are installable debug-signed
verification builds, not stable production-distribution APKs. Release APK signing
requires a separately supplied protected Android keystore; none was provided.
Android is not published to Google Play.

## Controlled App Store release

1. QA installs the exact TestFlight version/build on a physical iPhone.
2. Record workflow URL, source SHA, version/build, tester, device/iOS and results.
   Test cold launch/session restore/logout, camera/local-network permissions,
   real QR login, existing/unknown barcode scans, permitted edits/creation/price
   updates on disposable test records, offline failure, keyboard and sticky UI.
3. The team approves the tested version/build. Complete screenshots, privacy
   policy/App Privacy, metadata, compliance and reviewer instructions in App Store
   Connect. Keep reviewer credentials there, not in Git.
4. An authorized owner selects that build and manually submits for App Store
   review in App Store Connect. Select **Manually release this version**.
5. After Apple approval, the owner chooses **Release This Version** manually.

No review/submission lane is provided: the diagram's final approval steps happen
in App Store Connect, separate from automatic TestFlight deployment.

## Verification and limitations

Local checks: workflow lint, Fastfile Ruby syntax and mocked lane checks. Flutter
unit/widget tests remain offline. Android compilation requires an installed SDK;
iOS compilation/signing requires macOS, valid Apple assets and actual GitHub runs.
Successful IPA export, upload and physical iPhone installation cannot be certified
by YAML validation; record evidence from those runs before marking them complete.

Local checks on 2026-10-20: all four workflows passed Actionlint; Fastfile Ruby
syntax and mocked main-only, production-build, upload and failure-cleanup checks
passed. The Android build attempt (including an IPv4 retry) stopped in local Java
with `Unable to establish loopback connection`, before native compilation. A
hosted Android build is still required. No Apple signing/upload was performed.

References: [Fastlane build_app](https://docs.fastlane.tools/actions/build_app/),
[TestFlight upload](https://docs.fastlane.tools/actions/pilot/),
[GitHub workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).
