# Unit and widget testing strategy

The standard suite is `flutter test`. It covers domain rules, data mapping and
repositories, Riverpod state transitions, navigation and important widget states.
Tests run without live Odoo, Apple credentials, a camera, or a connected device.

## Organization

Mirror the ownership of production code for new tests:

```text
test/
  core/<area>/*_test.dart
  shared/*_test.dart
  app/*_test.dart
  features/<feature>/
    domain/use_cases/*_test.dart
    data/*_test.dart
    presentation/*_test.dart
  support/                         shared synthetic fixtures and fakes
integration_test/                  manual device journeys, outside CI
```

Existing Products tests directly under `test/features/products/` remain valid.
Do not move or rewrite working tests simply to change their location. Use focused
files for new tests, with observable behavior in test names and arrange/act/assert
structure. Test failure cases as well as the successful path.

## Coverage by boundary

| Boundary | Required checks | Existing examples |
| --- | --- | --- |
| Domain | Accepted boundaries, normalization, invalid values rejected before repository calls, correct delegation, typed failures and no unintended retries | Authentication and Home `domain/use_cases/`; Products `domain/use_cases/manage_product_details_test.dart`, `product_creation_test.dart`, `price_update_controller_test.dart`, `product_edit_controller_test.dart` |
| Repository | Mobile API v2 envelopes and error codes; optional fields; permission and transport failures; If-Match/idempotency headers; correct request mapping | `features/home/data/product_repository_test.dart`, `features/authentication/data/odoo_auth_repository_test.dart`, Products repository tests, `core/network/mobile_api_client_test.dart` |
| Riverpod | Loading/data/error transitions, provider overrides, duplicate submission, cancellation and disposal | `features/home/presentation/product_lookup_controller_test.dart`, session and Products controller tests |
| Widgets | Loading, populated/empty, safe errors, retry, validation, permissions, disabled/busy controls and successful updates | `features/products/product_details_test.dart`, `price_update_page_test.dart`, `product_edit_page_test.dart`, initialization page tests |
| Navigation | Auth restoration/redirect, protected routes and scanner return after edits/creation | `app_test.dart`, Products navigation and scanner return tests |

All six current domain use-case files have coverage in the existing suite. Some
Products suites combine domain, provider and widget checks; new focused suites
should follow the mirrored structure above. Coverage is evidence for review, not
a substitute for useful assertions or a reason to test implementation details.

## Dependencies and isolation

- Use existing Mocktail mocks for repository contracts and interaction checks.
  For multi-step state, reuse controlled fakes from `test/support/`.
- Inject Dio/data sources and secure-storage abstractions into repositories.
  Resolve/reject requests in a fake adapter or interceptor; never allow a fixture
  URL to reach the network. Do not use real credentials or inventory records.
- Create `ProviderContainer.test(overrides: [...])` per provider test. Override
  repositories/services with controlled dependencies. Listen while testing
  auto-dispose providers; await futures or completers rather than adding sleeps.
- Use `ProviderScope(overrides: [...])` in widget tests with the shared theme.
  Pump individual frames for pending states; only settle once work can finish.
  Check that private backend diagnostics are absent from error messages.
- Use fresh mutable state per test. Close Dio clients and subscriptions and
  dispose ordinary containers in teardown. `ProviderContainer.test()` registers
  disposal with the test runner. Control clocks through the existing clock
  provider. No order dependence or shared signed-in state.
- Do not add live-server, optical scanning or secure-platform-storage tests to
  this suite. Keep device integration manual in `integration_test/`.

## Local commands

From the repository root, using Flutter 3.47.5 / Dart 3.13.4:

```sh
flutter pub get --enforce-lockfile
dart format lib test integration_test
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter test --coverage
```

Run a focused suite during development:

```sh
flutter test test/features/products/domain/use_cases/manage_product_details_test.dart
```

After the final Dart edit, rerun the formatter and exact format gate before
committing. Keep the existing format-on-save settings and staged-format hook.

## CI

`.github/workflows/flutter_tests.yml` preserves PR #9's format, analyze, offline
unit/widget and coverage gates on pushes to `main`/`develop`/`staging`, PRs, their
merge queues and manual runs (never both a push and a PR run for one commit).
It also executes `python3 -m unittest discover -s tool/ci -p 'test_*.py'`,
`ruby -c fastlane/Fastfile` and `ruby tool/ci/test_fastlane.rb`.
The deployment tests use synthetic profiles/archives and mocked subprocesses and
Fastlane actions; they never sign, upload, contact Apple or access credentials.

Keep the independent native flavor builds and license workflow required statuses.
Only the legacy quality status is replaced by **Format, analyze and test**.
`ios-release.yaml`, `android-release.yaml`, `release_tags.py` and `android_apk.py` are covered by `tool/ci/test_release_pipeline.py`; pending export compliance is covered in `test_fastlane.rb`. `ios-testflight.yaml` (DEV/STG delivery) is covered by `tool/ci/test_testflight_cd.py`, `test_testflight_build_number.rb` and the channel lane tests in `test_fastlane.rb`. The workflows are linted with actionlint, and `tool/ci/test_workflows.py` and
`test_versioning.py` guard triggers, secrets, signing protections and the app
version (see "Stage 1 CI foundation" in [Deployment](deployment.md)).
Environment protection rules (reviewers) still require owner configuration.
See [Deployment](deployment.md) for manual protected release controls.

## Real-backend validation

CI never calls a live Odoo. Before a release or after backend changes, validate
against the local development Odoo (Docker `dev-odoo-1`, addons of
Orange-POS/odoo_addons PR #192):

1. A local, git-ignored Playwright harness in `tool/e2e`: `public` contract checks without
   login, then `npm run login` (you sign in) and the `pos` journey, which uses a
   real POS QR challenge and one dedicated `OOE2E-…` product per run.
2. Flutter integration tests on a device (fake repositories, no live data):
   `flutter test integration_test --flavor development --dart-define=TEST_FLAVOR=development -d DEVICE_ID`.
3. Manual device journey with the real backend: scan the POS QR, look up and
   search products, create/edit/price/count a dedicated test product, toggle
   Wi-Fi for offline read-only and recovery, restart (session restore), log out.

Never run these checks against staging or production data.

## Adding a feature or fixing a regression

1. Identify domain boundaries, failure paths and affected UI states.
2. Add a focused test that fails for the regression or missing behavior.
3. Implement the change with injected dependencies; keep API calls out of widgets.
4. Run focused tests, then the complete local quality gates above.
5. Review coverage changes for missing paths; do not add arbitrary exclusions or
   thresholds to make CI pass. Record physical-device checks separately.

Native builds and deployment are separate workflows documented in
[deployment.md](deployment.md). Passing this suite does not prove Android/iOS compilation, real camera
behavior or production backend compatibility.

Local verification on 2026-10-20: all 355 unit/widget tests passed with coverage,
including all six domain use-case source files. The exact format gate reported
134 files with zero changes. Static analysis and workflow lint passed. GitHub CI
execution is verified separately after pushing; no hosted result is implied by
these local checks.
