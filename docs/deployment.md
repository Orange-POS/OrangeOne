# Android and iOS deployment

## Workflow behavior

| File/job | Trigger | Output / access |
| --- | --- | --- |
| `quality.yaml` | Every push, every PR, main merge queue, manual | Format/analyze, offline unit/widgets, LCOV, release-script tests, Ruby syntax and Fastlane lane guards; device integration remains manual |
| `android.yaml` | Every push, PR to main, main merge queue, manual | Development/staging/production debug APK artifacts; no Play Store upload |
| `ios.yaml` / `ios` | Every push, PR to main, main merge queue | Unsigned release `.app` ZIPs on GitHub-hosted `macos-26`; no Apple secrets |
| `ios.yaml` / `candidate` + `beta` | Manual `testflight`: select an open PR number or leave blank for main; protected signing approval | Selected commit compiled as production, then exported/signed on a fresh runner and uploaded to internal TestFlight |
| `ios.yaml` / `submit` | Manual `submit_for_review` from main after release checks, iPhone confirmation and separate environment approval | Submit existing tested build for review; public release remains manual |
| `license_check.yaml` | Every push, PR to main, main merge queue, manual | Flutter dependency license policy |

A merge into main triggers push checks. Workflows use read-only repository access;
there is no `pull_request_target` or secrets in untrusted PR jobs. Production code
comes from main or the explicitly selected open PR head targeting main, pinned to its immutable SHA. The workflow itself must still be dispatched from main so its control/signing scripts remain trusted. PR TestFlight builds are never automatic. Signing jobs are
serialized and not cancelled by a new dispatch. Unsigned apps are ZIP-wrapped to
preserve their bundle permissions/symlinks in GitHub artifacts.

Android APKs are debug-signed installable verification artifacts, **not a stable
production distribution signature**. They require no credentials and no Google
Play account. Installing over a differently signed APK may require uninstalling
it. If stable employee-distribution release APKs become necessary, add a protected
Android signing key workflow separately; do not reuse debug keys for that purpose.

## Apple setup (owner action before the first signed run)

1. Enroll the organization in the Apple Developer Program and accept current
   agreements. Confirm ownership of production bundle ID `com.orangeone.app`.
   Create its App Store Connect app record. If that ID is unavailable, change all
   bundle/signing references consistently before building; no Apple account or
   app record is created by these files.
2. Create an **Apple Distribution** certificate and export it with its private key
   as a password-protected `.p12` from a trusted Mac. A `.cer` without its private
   key cannot sign. Create an **App Store Connect distribution** provisioning
   profile for the exact production bundle ID, team, capabilities and certificate.
   Development, ad-hoc, enterprise, wildcard, expired or development-flavor
   profiles are rejected. Runner currently uses the keychain access group.
3. Create an App Store Connect team API key with an appropriate role (App Manager
   for submission; least required access for upload). Record Key ID and Issuer ID
   and securely download its `.p8` private key. Apple ID passwords and Fastlane
   session cookies are not used. Ensure the account has app access and agreements
   required for both upload and review submission.
4. In GitHub **Settings → Environments**, create `ios-production` and
   `ios-app-store`. Restrict deployment branches to **main**, require a reviewer,
   prevent self-review where supported, and disallow admin bypass if appropriate.
   These are repository settings you must configure; YAML cannot enforce reviewer
   rules until the environments are protected. Use separate approvers for store
   submission where practical.
5. Add the following **environment secrets**. Keep the same API key secrets in
   both environments, or use separate limited-access keys:

| Secret | `ios-production` | `ios-app-store` | Value |
| --- | --- | --- | --- |
| `IOS_CERTIFICATE_BASE64` | Required | Not needed | Base64 of `.p12` including private key |
| `IOS_CERTIFICATE_PASSWORD` | Required | Not needed | Password used when exporting the `.p12` |
| `IOS_PROVISION_PROFILE_BASE64` | Required | Not needed | Base64 of production App Store `.mobileprovision` |
| `APPLE_TEAM_ID` | Required | Not needed | 10-character Developer Team ID |
| `APP_STORE_CONNECT_KEY_BASE64` | Required | Required | Base64 of `.p8` private key |
| `APP_STORE_CONNECT_KEY_ID` | Required | Required | API key's Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Required | Required | API key's Issuer ID |

On a trusted Mac, copy base64 to the clipboard without writing credentials to the
repository or terminal logs:

```bash
base64 -i /secure/location/distribution.p12 | tr -d '\n' | pbcopy
base64 -i /secure/location/production.mobileprovision | tr -d '\n' | pbcopy
base64 -i /secure/location/AuthKey.p8 | tr -d '\n' | pbcopy
```

Run each command separately, paste into the corresponding GitHub secret, then
clear the clipboard. On Windows, an equivalent is
`[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\file.p12')) | Set-Clipboard`.
Never paste actual values in an issue, PR, chat, tracked JSON or workflow file.
`.gitignore` covers common Apple key/certificate formats and generated outputs,
but it cannot prevent explicitly forced commits; inspect changes before pushing.

## First TestFlight upload

1. Merge the tested pipeline changes into main. Configure the environments and
   secrets above. Ensure quality, Android and unsigned iOS checks are green.
2. Open **Actions → OrangeONE iOS → Run workflow**. Select workflow branch **main** and
   operation **testflight**. Set **pr_number** to the open PR number (for example `42`) to build that PR, or leave it blank to build main. Enter a marketing version such as `1.0.0` and a new
   build integer from `1` to `9999`. Increment the number for every upload; reruns
   of an already uploaded version/build will be rejected by Apple. The pipeline
   deliberately requires an explicit number rather than guessing App Store state.
3. Review the selected PR/main SHA in the workflow summary and approve
   `ios-production`. The candidate job runs formatting, analysis, unit/widgets and
   `flutter build ipa --no-codesign` for the **production** flavor without Apple
   credentials. A separate fresh runner checks out only trusted workflow code,
   validates the archived bundle/version/build and contained paths, loads signing
   material, and calls Xcode's **export-only** operation. It never rebuilds or runs
   PR scripts with signing secrets. Fastlane uploads the exported IPA. Protected
   jobs do not restore PR-writable dependency caches. The production environment
   JSON is nonsecret and leaves backend discovery to QR.
4. Fastlane waits for processing, uploads to **internal** TestFlight and does not
   enable external distribution or public release. Configure an internal tester
   group/build assignment in App Store Connect, resolve export compliance if
   requested, and install using Apple's TestFlight app on a physical iPhone.
   TestFlight processing/upload success is not proof of installation or scanner
   operation. The retained IPA/dSYM artifact is available for 7 days; it does not
   contain the certificate/private API key. Store crash symbols securely longer if
   needed. A TestFlight IPA is not an ad-hoc sideload package.

Signing files are created under runner temp with restrictive permissions, no raw
secrets are printed, and cleanup restores the keychain search list and deletes the
imported profile, temporary keychain, certificate and API key on success/failure.
Hosted-runner destruction is the final isolation boundary if the job is abruptly
terminated. Do not switch this job to a persistent/self-hosted runner without a
separate credential lifecycle review. Never enable shell tracing or upload runner
temp directories, signing logs or raw environment dumps.

## Physical iPhone release gate

Record version/build, workflow run URL and source SHA, iPhone model, iOS version,
test date, tester and results in the release record. Use a dedicated test Odoo
instance/company and disposable products. TestFlight uses production app settings,
but its POS QR can point to that test server. No live stock changes are required.

- Install and cold-launch from TestFlight; splash, session restore and layout work.
- Grant camera and local-network permissions, then test denied permissions and
  recovery through Settings. Scan a freshly generated POS QR using the real camera.
- Scan an existing product barcode optically; check name, CHF price, tax and stock.
- Scan an unknown barcode; verify prefilled creation and required-field validation.
  If authorized, create a disposable test product, Done → details → Back → rescan
  the same barcode; camera restarts and stale not-found actions are absent.
- Edit permitted name/tax and update price with confirmation on test products;
  verify permission denial, duplicate-tap protection, backend errors and refresh.
- Verify sticky header/actions, keyboard, scrolling and glass surface on iPhone.
- Close/reopen with a valid session; then test expired/offline startup, 15-second
  validation deadline, logout and state reset without repeated server retries.
- Check an offline authenticated operation resets the session on first failure;
  check production builds show no development diagnostics or application debug logs.

The controlled automated integration journey does not prove optical QR/barcode
recognition or TestFlight installation. The confirmation input is a human
attestation, not an automated device test. Do not mark it true without evidence.

## App Store review and controlled public release

Complete App Store Connect screenshots, description, privacy policy, App Privacy,
ratings, export-compliance information, support URLs and reviewer credentials/
instructions for a test POS account. Keep reviewer credentials in App Store
Connect, not GitHub logs. Explain local-network/camera access and the existing LAN
HTTP/ATS behavior where required; prefer HTTPS for deployment. Check third-party
privacy manifests and Apple validation results. Do not invent compliance answers
or mark encryption exemption automatically.

After the exact version/build passes the iPhone checklist, dispatch the same
workflow from **main**, operation **submit_for_review**, leaving **pr_number** empty and supplying that version
and build and checking `iphone_smoke_test_confirmed`. An `ios-app-store` reviewer
must verify the test evidence before approving. `fastlane ios submit` selects the
existing App Store Connect binary, performs prechecks and submits for Apple review;
it neither rebuilds a potentially different binary nor uploads one.

`automatic_release: false` keeps the approved build pending developer release.
After Apple approval, the release owner checks the selected build in App Store
Connect and chooses **Release This Version** manually. This final public-release
step deliberately remains outside automated jobs. Stop/reject a pending approval
to cancel before submission. After a bad beta upload, upload a higher build number;
after public release, follow Apple's supported removal/phased-release controls
and ship a corrected higher build. Never try to overwrite an existing uploaded IPA.

## Reproducing tools and validation limits

Flutter is pinned to 3.47.5; native iOS compilation/signing uses GitHub-hosted
`macos-26` with its selected Xcode 26+ toolchain (version printed in logs).
Fastlane is pinned in `Gemfile`, with macOS/Linux dependencies locked in `Gemfile.lock`; Ruby 3.3 is set in workflows. Bundler installs from this lockfile. Update it deliberately with `bundle update fastlane` and review the diff. Compilation uses the existing production scheme and bundle identifier. The signing job exports the already-built archive; it does not change or build an Xcode project.

Local quality: `flutter analyze --fatal-infos --fatal-warnings`,
`flutter test --coverage`, `python3 -m unittest discover -s tool/ci -p 'test_*.py'`,
`ruby -c fastlane/Fastfile`, `ruby tool/ci/test_fastlane.rb`, and Actionlint for the four workflow files.
Actual GitHub runs, Apple signing/export, TestFlight upload/installation, optical
iPhone flows and Apple review/public release require credentials, hosted macOS,
a physical iPhone and owner action. Their status must be recorded from real runs;
source/configuration validation cannot satisfy those device/distribution criteria.

Implementation references: [GitHub Apple signing](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[Fastlane signing/export](https://docs.fastlane.tools/actions/build_app/),
[TestFlight](https://docs.fastlane.tools/actions/pilot/),
[App Store submission](https://docs.fastlane.tools/actions/upload_to_app_store/).


Local validation for this implementation (2026-10-19): all 348 Flutter tests passed
with coverage; static analysis reported no issues. The six Python release/profile/
cleanup tests and three Fastfile lane-guard tests (22 assertions) passed. Fastfile
Ruby syntax and Actionlint 1.7.12 validation of all four workflows passed. The
Fastfile tests use recording actions, not Apple services. No workflow was pushed
or dispatched, no signing credential was used, and no signed IPA/TestFlight/
physical-iPhone/store result is claimed. Those acceptance criteria remain pending
owner secret setup and actual hosted/device runs.

### Manual PR build rules

- Any selected PR must be open and target this repository's `main` branch.
- Select workflow branch **main**; `pr_number` selects the application source, not
  the workflow source. No secrets are required in a contributor's fork.
- A new PR commit or a closed PR invalidates the candidate before signing. Rerun
  manually and review the new immutable SHA; do not approve stale source.
- Main and PR uploads share `com.orangeone.app` and the production flavor. Use a
  distinct build number for every upload. TestFlight's changelog names PR/main
  and the SHA. Development/staging TestFlight distribution is not enabled.
- Existing automatic unsigned iOS checks remain. They do not sign or upload to
  TestFlight. Integration/device tests remain manual.
- PR selection is available for TestFlight only. App Store submission stays a
  separate main-dispatched approval operation with the existing iPhone evidence
  requirement; its release owner must verify the chosen build's source.

The split unsigned-archive/export path is validated locally through mocked export
commands, archive checks and workflow linting. Actual signing/export and upload
still need a hosted macOS run with Apple credentials; no success is claimed here.
