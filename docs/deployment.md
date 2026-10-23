# Android and iOS deployment

## Testing and deployment ownership

PR #9's testing strategy and PR #15's native build/deployment implementation
are merged into main. PR #19 preserves those gates and adds offline data access,
recovery fixes and the production iOS bundle identity correction.
The canonical workflow names remain `android.yaml`, `ios.yaml`,
`license_check.yaml` and `flutter_tests.yml`; duplicate replacement
workflows are retired to avoid duplicate builds and automatic signing.

Distribution remains manual from main, with protected approval and separate
secret-free compilation and signing/export runners. Version/build numbers are
explicit inputs; reserve a unique build number in App Store Connect. Local
regression tests never trigger signing or upload. Main is integrated into
PR #19 using a normal merge; no history is rewritten and this does not merge
PR #19 into main.

## Workflow behavior

| File/job | Trigger | Output / access |
| --- | --- | --- |
| `flutter_tests.yml` | Every push, every PR, main merge queue, manual | Format/analyze, offline unit/widgets, LCOV, release-script tests, Ruby syntax and Fastlane lane guards; device integration remains manual |
| `android.yaml` | Every push, PR to main, main merge queue, manual | Development/staging/production debug APK artifacts; no Play Store upload |
| `ios.yaml` / `ios` | Every push, PR to main, main merge queue | Unsigned release `.app` ZIPs on GitHub-hosted `macos-26`; no Apple secrets |
| `ios.yaml` / `candidate` + `beta` | Manual `testflight`: select an open PR number or leave blank for main; protected signing approval | Selected commit compiled as production; exact uploaded build assigned to the selected tester group, then exported/signed on a fresh runner and uploaded to internal TestFlight |
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
   agreements. Confirm ownership of production bundle ID `ch.orangepos.productscanner`.
   Preserve its existing App Store Connect record and bundle ID. Development and
   staging App IDs/records may remain registered but are unused by signed CD.
2. Reuse the existing valid **Apple Distribution** certificate and its existing
   password-protected `.p12` containing the private key. Keep the existing
   production App Store Connect distribution profile. No new certificate or
   profile is required for tester groups. Debug/development signing, ad-hoc,
   enterprise, wildcard, expired and nonproduction profiles are rejected.
   Runner currently uses its own keychain access group.
3. Create an App Store Connect team API key with an appropriate role (App Manager
   for submission; least required access for upload). Record Key ID and Issuer ID
   and securely download its `.p8` private key. Apple ID passwords and Fastlane
   session cookies are not used. Ensure the account has app access and agreements
   required for both upload and review submission.
4. In GitHub **Settings → Environments**, verify `ios-production` and `ios-app-store`. Leave unused
   `ios-development` and `ios-staging` resources and Secrets untouched. Restrict deployment branches to **main**, require a reviewer,
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
privacy manifests and Apple validation results. Do not invent compliance answers;
the encryption exemption is the reviewed Info.plist declaration described below.

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
- Main and PR uploads share `ch.orangepos.productscanner` and the production flavor. Use a
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


## Secret-free review validation

Release tests cover profile/team/bundle/expiry/device-list rejection, manual-main
restrictions, required iPhone attestation, archive identity/executable validation,
export-only invocation, missing/empty/multiple IPA rejection and cleanup after
partial installation or damaged cleanup state. Signing cleanup errors fail the
job rather than reporting success. A destroyed state file can prevent restoring
the old keychain list or locating an installed profile; use ephemeral hosted
runners, inspect failed cleanup and never reuse a runner for another release.

Local Windows validation cannot prove Xcode export, real Apple asset validity,
TestFlight processing, protected-environment approval or physical iPhone flows.
These require a reviewed manual run on GitHub macOS after owner approval; do not
trigger distribution merely to validate this change. No public release occurs:
`automatic_release: false` is preserved and the owner releases in App Store Connect.


## One production application, three TestFlight groups

Signed CD always compiles scheme `production`, `lib/main_production.dart`, and
bundle ID `ch.orangepos.productscanner`, using the existing production profile,
certificate and protected `ios-production` environment. Android CI and all three
unsigned iOS flavors are unchanged. No native identifiers or schemes are changed.

A **Flutter flavor** controls compiled application configuration and native
identity. A **TestFlight group** controls tester access to builds of the same
App Store Connect app. The `target_group` input changes only distribution, never
the Flutter flavor, backend configuration, signing identity or application data.

| `target_group` | Exact group name | Signed application |
| --- | --- | --- |
| `dev` | Dev Testers | Production OrangeONE |
| `staging` | Staging Testers | Production OrangeONE |
| `production` (default) | Production Testers | Production OrangeONE |

### Owner setup before deployment

1. In the existing production App Store Connect record, open TestFlight and
   create or verify the three exact group names above. Use internal groups for
   eligible App Store Connect team users. Disable automatic distribution / access
   to all builds on the selected groups so builds can be assigned explicitly.
2. Check automatic distribution on every other group, existing direct tester
   access and Apple's built-in internal-tester access. The workflow does not
   remove anyone's access, change membership or revoke access granted by Apple.
   It adds only the selected group, but **cannot promise exclusive access** if
   account settings, overlapping memberships or other users grant more access.
3. Internal testers must be eligible App Store Connect users with app access.
   External testers require an external group and applicable Beta App Review.
   The helper accepts external groups only when the exact build is already
   eligible for external testing. Otherwise it fails with manual-review guidance;
   it does not silently submit Beta App Review or publicly release anything.
4. Verify the existing production profile matches the production bundle, team,
   keychain entitlement and imported certificate. Preserve repository Secrets;
   do not change the production profile Secret without verifying compatibility.
5. Verify `ios-production` / `ios-app-store` branch restrictions and reviewer
   approvals in GitHub Settings. Keep unused development/staging environment
   profile Secrets untouched. Repository credentials remain reachable by other
   workflows that explicitly reference them; protect main and review workflow
   changes. Candidate jobs never reference those Secrets.

### Dispatch and exact-build assignment

After review and integration into protected main, select `ios.yaml` -> Run workflow:
branch **main**, operation `testflight`, target group, version and a new build number.
Leave PR blank to compile main, or select an open PR targeting main. Its SHA is
pinned and checked again before signing. Candidate compilation is credential-free;
privileged jobs run scripts from the dispatched main SHA on a fresh runner.
One version/build sequence is shared by all groups because this is one app.

Archive checks, certificate/profile matching, entitlement checks, export-only
signing, exported IPA verification and unconditional cleanup remain enabled.
After export, Fastlane Pilot uploads with distribution/review disabled and does
not rely on upload-time automatic group assignment. The trusted helper uses the
existing pinned Spaceship client for Apple's official App Store Connect API:

- Resolve the production app and the one exact allowlisted group; missing,
  duplicate or automatic/all-build groups fail preflight before upload.
- Query builds by that app ID, iOS platform, marketing version and build number.
  Wait up to 15 minutes for that exact build and testing eligibility; never use
  an unrelated latest build. Invalid, failed, expired or ambiguous builds fail.
- Export compliance comes from the reviewed `ITSAppUsesNonExemptEncryption`
  declaration in the production Info.plist (see "Encryption declaration" below),
  so new builds need no manual answer. If Apple still reports missing compliance
  (for example a build uploaded before the declaration), the helper stops without
  assuming an answer. External review eligibility is checked separately.
- Add only the selected group's relationship to that exact build ID, then read
  the group/build relationship back. API errors or unconfirmed assignments fail
  the workflow. An existing matching assignment is treated idempotently: after
  identity, validity, compliance and group validation, check the relationship
  before waiting for initial readiness. Internal `IN_BETA_TESTING` builds can
  retain their existing assignment or receive another selected allowed group;
  no upload is replayed and new assignments still require read-back confirmation.

If processing/compliance/review or assignment fails after upload, the binary may
already be in TestFlight. Inspect **that exact version/build** in App Store Connect
and complete any required compliance/review. Then use `distribute_existing` as
described below; do not re-upload the same version/build or choose a different
latest build as a substitute. API assignment success does
not guarantee notification delivery or installation; verify on a tester device.

### Testers, backend safety and public release

Testers install OrangeONE from TestFlight. Under the app's Previous Builds / build
selection, they can select another available build granted to them. Installing a
build replaces the installed version of this same app; three copies cannot coexist
under one bundle ID. App data/session may persist across build changes. A tester
belonging to multiple groups can have access to builds assigned to any of them.

**Dev Testers and Staging Testers still receive production-flavor binaries.**
Group selection does not establish a test backend or sandbox, and selected PR
code can change app behavior. Follow existing QR-selected POS/session rules;
use an authorized test POS and test inventory for destructive testing. Verify the
connected backend before editing real stock/prices. No authentication or product
logic is changed by this distribution strategy.

Operation `submit_for_review` remains a separate manual production action through
`ios-app-store`, requiring an already tested version/build and iPhone confirmation.
The target-group input is irrelevant to submission. Selecting Production Testers
with operation `testflight` never submits or publishes the public App Store app.
Public release remains manual (`automatic_release: false`).

After `bundle install` installs the pinned Fastlane dependency, the existing Ruby
CI entry point (`ruby tool/ci/test_fastlane.rb`) also loads the controlled group
coordinator tests. These load the actual Fastlane 2.241.1 `BuildBetaDetail` model
without initializing an Apple client or making network requests. External states
`BETA_APPROVED`, `READY_FOR_BETA_TESTING` and `IN_BETA_TESTING` permit assignment.
Missing details/state and `PROCESSING` wait within the deadline; review-required,
pending/rejected review, compliance and terminal failures stop with manual guidance.
Unknown external states fail closed. No absent external-readiness method is called. Hosted
macOS verification is still required for real signing, API permissions, group
eligibility/processing, TestFlight installation and protected-environment rules.
Firebase is not integrated by this change.


### Recover assignment without another upload

After this change is reviewed and integrated into protected main:

1. In GitHub Actions, open **OrangeONE iOS** and select **Run workflow** on `main`.
2. Choose operation `distribute_existing`, the target group (`dev`, `staging`, or
   `production`), and the **existing** marketing version/build number. For the
   reported uploaded build, enter version `1.0.6` and build `33`.
3. Leave PR number empty. Approve the protected `ios-production` job as required.
4. The job loads only the App Store Connect API key from trusted-main scripts.
   It does not download a candidate, compile, import a distribution certificate,
   sign/export an IPA, upload a binary, submit Beta App Review, or submit a public
   App Store release. Production submission remains a separate approved action.
5. It resolves the allowlisted group and exact production app/version/build,
   waits within the existing 15-minute deadline for processing, checks compliance
   and internal/external eligibility, and adds only the selected relationship.
   Success is reported only after read-back confirms that exact build/group.
   Already assigned eligible builds succeed without another relationship write.

Compliance pending, review required/rejected, unknown states, changed groups,
expired/invalid builds, API errors, and unconfirmed assignments fail safely.
Missing build/eligibility metadata waits within the deadline, rather than
bypassing compliance checks. Complete compliance or Beta App Review in App Store
Connect and rerun **this mode**, not `testflight`, with the same version/build.
No latest-build fallback or automatic repeat upload is performed. A failed
relationship request may have reached Apple: rerunning this idempotent mode first
reads the relationship instead of blindly repeating a mutation.

Apple or another account user may independently grant access through automatic
all-build settings, direct access or overlapping memberships. The workflow does
not remove that access and cannot promise exclusive access. Review automatic
settings on all groups; the selected group must not have all-build access.

### Encryption declaration and France availability

OrangeONE uses standard AES-256-GCM in Dart for encrypted product snapshots;
this is **not** an Apple-OS-only or no-encryption application. Select standard
algorithms beyond Apple OS encryption in Apple's questionnaire. Excluding France
is a distribution decision, not an algorithm change. The owner must verify that
France is actually excluded from App Store availability (and applicable testing
territories); the workflow does not edit territory settings.

Apple's documentation table lists a French declaration for standard algorithms
outside Apple's OS **only when distributing on the App Store in France**:
https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/

On the stated standard-algorithm/non-France facts, that table does not require
that French document. `ITSAppUsesNonExemptEncryption = false` is appropriate
**because the responsible owner confirmed the app uses only encryption exempt from
Apple's documentation requirements**, not because the app lacks encryption.

**Approved declaration (2026-10-23):** the owner confirmed this classification and
that France is excluded from App Store availability. `ios/Runner/Info.plist` now
declares `ITSAppUsesNonExemptEncryption = false` (no compliance code). Builds
compiled from that source are processed as compliant, so `testflight` reaches
`READY_FOR_BETA_TESTING` and assigns the selected group without a manual
App Store Connect step. `tool/ci/test_release.py` fails if the declaration is
removed or changed. Revisit this, through review, before adding France or any
encryption beyond HTTPS and the local AES-256-GCM product cache; if Apple then
requires documentation, submit it under App Encryption Documentation, obtain
Apple's approved code and review the corresponding true flag/code. Never invent
the code or bypass the questionnaire. See Apple's key semantics:
https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption

Builds uploaded before this declaration keep their own (missing) answer; source
changes cannot amend those binaries. For such a build, answer the export
compliance questionnaire for that exact version/build in App Store Connect, then
run `distribute_existing` with the same version/build; do not reupload it.
The helper still stops on `MISSING_EXPORT_COMPLIANCE` as a safety net.

Export verification compares the final IPA's boolean/code (including missing
keys and exact types) to the trusted production plist. An omitted/changed or
unapproved declaration fails before upload. This also prevents a PR candidate
from independently changing a declaration without trusted-main review.
No certificate, provisioning profile or GitHub Secret changes are needed.
