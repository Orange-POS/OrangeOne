# Android and iOS deployment

## Workflows

- quality.yaml: format, analysis, offline Flutter tests, coverage and Fastlane syntax on every push/PR. Device integration remains manual.
- android.yaml: installable debug APK artifacts for existing flavors; no Play Store publishing. Production Android signing is not configured.
- ios.yaml: automatic production unsigned builds; manually selected PR/main production TestFlight builds and App Store submission.
- license_check.yaml: dependency license checks.

Deployment logic lives directly in YAML and fastlane/Fastfile. The separate deployment helper scripts were removed. Existing branding helpers are unrelated and remain in use.

## Apple setup

Use your existing seven repository secrets without renaming:

| Secret | Value |
| --- | --- |
| APPLE_TEAM_ID | Apple Developer Team ID |
| IOS_CERTIFICATE_BASE64 | Base64 Apple Distribution p12 with private key |
| IOS_CERTIFICATE_PASSWORD | p12 export password |
| IOS_PROVISION_PROFILE_BASE64 | Base64 App Store distribution profile |
| APP_STORE_CONNECT_KEY_BASE64 | Base64 App Store Connect p8 API private key |
| APP_STORE_CONNECT_KEY_ID | API Key ID |
| APP_STORE_CONNECT_ISSUER_ID | API Issuer ID |

The certificate, profile and App Store Connect app must match com.orangeone.app. Only one production app ID is required. Accept Apple's agreements and grant the API key app upload/submission access.

Create protected GitHub environments ios-production and ios-app-store with required reviewers and deployment branch main. Repository secrets work directly. Identically named environment secrets override them; remove stale values. Prefer environment-scoped credentials when possible. Never commit credentials.

## Run TestFlight

1. Merge workflow infrastructure into main first.
2. Open Actions, then OrangeONE iOS - Unsigned and TestFlight, then Run workflow.
3. Select branch main and operation testflight.
4. Enter an open PR number targeting main to test that PR; leave blank to build main.
5. Enter version x.y.z and a new build number from 1 to 9999 for every upload.
6. Review the pinned source SHA before approving ios-production signing.
7. Assign the processed build to internal testers in App Store Connect. Install using Apple's TestFlight app. External testers need separate beta review/group setup.

Unsigned artifacts cannot install on an iPhone. PR and main TestFlight builds use the same production app ID, so installing one replaces the other. Signed uploads never run automatically for every PR.

PR source is tested and compiled without Apple credentials. A fresh runner checks out trusted main workflow/Fastlane code, validates the archive, installs an ephemeral keychain/profile, exports the signed IPA and uploads it. Cleanup runs on success/failure; hosted runner destruction covers abrupt termination. Keep secrets out of logs and do not enable shell tracing.

## Release from main

After merging application changes, run testflight with no PR number. Record workflow URL, main SHA, version/build, tester, iPhone model/iOS version and results. Verify cold launch, session restore/logout, permission denial/recovery, optical QR/barcode scans, existing/unknown products, authorized test-product creation/edits/price updates, duplicate requests, offline handling, keyboard and sticky controls.

Dispatch submit_for_review from main with no PR number, the exact tested main version/build and iPhone confirmation. The approver must verify the selected binary's source and test evidence. This submits an existing build without rebuilding; public release stays manual in App Store Connect after Apple approval. Complete store metadata, privacy details, screenshots, compliance and reviewer access separately.

## Validation limits

Workflow lint and Ruby syntax checks do not prove signing or TestFlight installation. Actual export/upload needs GitHub-hosted macOS, valid Apple credentials and a physical iPhone. No successful signing/upload/device run is claimed without recorded evidence. Flutter and Fastlane versions remain pinned.
