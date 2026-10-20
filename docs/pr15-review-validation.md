# PR #15 review validation

Branch: `feature/android_iOSbuild_CD`. Dependency: PR #9, testing strategy and
retained native/release/license baseline. No commit, push, merge or release was
performed during this review. PR #9's pre-existing uncommitted work is preserved
in the stash named `Preserve PR9 working changes before PR15 review`.

## Findings and implementation

Issues #10/#11 identify production-only iOS coverage, lost executable release
regressions and removal of native/release/license capabilities. PR #15 also
triggered signing automatically and compiled with credentials available. The
required remedy reuses the PR #9/main split pipeline rather than introducing a
second release system. The final PR dependency must be reconciled before merge;
no branch history was rewritten or dependency merged locally.

| File | Change |
| --- | --- |
| `.github/workflows/android.yaml` | Restore three-flavor Gradle validation, entrypoints/configs, push/PR/merge queue/manual events and seven-day APK artifacts. |
| `.github/workflows/ios.yaml` | Restore unsigned flavor matrix and manual production release: immutable candidate source, secret-free archive, protected export-only signing, separate confirmed submission and always-cleanup. Pass requested version/build to export validation. |
| `.github/workflows/license_check.yaml` | Preserve strict direct/dev/transitive license enforcement with retrieval failures fatal. |
| `.github/workflows/flutter_tests.yml` | Keep format/analyze/offline test/coverage gates; add secret-free Python and Fastlane regression checks. |
| `.github/workflows/android_apk.yml` | Retire production-only replacement in favor of canonical `android.yaml`. |
| `.github/workflows/ios_unsigned.yml` | Retire production-only replacement in favor of the unsigned matrix in `ios.yaml`. |
| `.github/workflows/ios_testflight.yml` | Retire automatic signing in favor of manual protected jobs in `ios.yaml`. |
| `Gemfile` | Retain Fastlane 2.241.1; restore baseline Ruby version constraint. Lockfile contents unchanged. |
| `fastlane/Fastfile` | Restore manual-main guards, export-only beta upload, confirmed review submission and manual public release. |
| `tool/ci/validate_release.py` | Restore manual-main, operation, version/build and iPhone attestation validation. |
| `tool/ci/ios_signing.py` | Restore private temporary assets/profile validation/cleanup; ensure corrupted cleanup state cannot skip deleting keychain/private files. |
| `tool/ci/prepare_archive.py` | Restore archive path/symlink/identity checks; additionally reject absent/empty or unsafe executable names. |
| `tool/ci/export_ipa.py` | Export an existing validated archive only; reject stale IPA output and missing/empty/ambiguous export results. |
| `tool/ci/test_archive.py` | Restore and extend archive/export regression tests with synthetic filesystem fixtures and mocked Xcode. |
| `tool/ci/test_release.py` | Restore profile/release/cleanup tests; add partial-install and corrupt-state cleanup regressions. |
| `tool/ci/test_fastlane.rb` | Evaluate actual lanes using recording actions; reject unauthorized submit and failed/invalid exports before upload. |
| `tool/ci/test_native_flavors.py` | Verify actual entrypoints/configs, Gradle flavors, shared Xcode schemes, release configurations and matrix/event wiring. |
| `docs/deployment.md` | Document dependency, canonical workflow names, owner approval/secrets, manual release, tests and limitations. |
| `docs/testing.md` | Preserve PR #9 isolation strategy; document executable deployment regressions and independent native/license checks. |
| `README.md` | Correct workflow links and automatic-upload claims. |
| `AGENTS.md` | Record retained flavor/license checks and manual protected split release controls. |
| `docs/pr15-review-validation.md` | This review evidence and file-by-file handoff. |

## Local checks (2026-10-20)

- `flutter pub get --enforce-lockfile`: passed.
- `dart format lib test integration_test`: 134 files, zero changes.
- `dart format --output=none --set-exit-if-changed lib test integration_test`: passed.
- `flutter analyze --fatal-infos --fatal-warnings`: no issues.
- `flutter test --coverage --reporter expanded`: 355 passed.
- `python -m unittest discover -s tool/ci -p 'test_*.py'`: 20 passed.
- `ruby -c fastlane/Fastfile`: syntax OK.
- `ruby tool/ci/test_fastlane.rb`: 6 passed, 32 assertions, zero failures/errors.
- Actionlint 1.7.12, all four workflow files: passed.
- `dart pub global run very_good_cli:very_good packages check licenses --dependency-type=direct-main,direct-dev,transitive --allowed=MIT,BSD-3-Clause,BSD-2-Clause,Apache-2.0`: all 89 allowed (66 BSD-3-Clause, 4 Apache-2.0, 19 MIT).
- `git diff --check`: passed.

Android commands use `flutter build apk --debug --flavor <flavor> --target
lib/main_<flavor>.dart --dart-define-from-file=config/<flavor>.example.json`.
Windows validation uses the installed Android Studio JBR and a command-local
`jdk.net.unixdomain.tmpdir` workaround; neither changes Gradle configuration.
All three passed: development (168.2s), staging (62.9s), production (60.2s).
The generated debug APKs remain ignored build artifacts.

## Remaining hosted checks and risks

- Compile all iOS schemes on GitHub macOS; checked-in XML tests are not Xcode compilation.
- Owner must configure required reviewers and main-only restrictions on
  `ios-production` and `ios-app-store`; YAML names alone do not enforce approval.
- Actual certificate/profile/API key validity, IPA signing/export, TestFlight
  processing and physical iPhone camera/essential flows require approved hosted
  release/device verification. None was performed or triggered here.
- Reserve a unique version/build for manual uploads. Review the resolved source
  SHA, including explicitly selected PR candidates, before protected approval.
- Existing Gradle 8.14.3 and AGP 8.12.0 produce future-support warnings; upgrades
  are a separate native dependency task, not silently bypassed.
- Cleanup attempts all recoverable steps and fails visibly. Abrupt runner loss or
  damaged state relies on hosted-runner destruction; do not use persistent runners.

Suggested commit: `ci: restore multi-flavor validation and protected iOS release guards`
