# Testing strategy

The standard offline suite is `flutter test`; coverage is produced by
`flutter test --coverage`. It must not require Odoo, an account, platform camera,
network connection or real secure storage. No inventory writes belong in CI.

## Ownership and folder conventions

Mirror implementation ownership under `test/`:

```text
test/features/<feature>/domain/use_cases/*_test.dart
test/features/<feature>/data/*_test.dart
test/features/<feature>/presentation/*_test.dart
test/core/<infrastructure>/*_test.dart
test/shared/*_test.dart
test/app/*_test.dart
test/support/                         reusable fixtures and controlled fakes
integration_test/                     controlled app journeys and device-only tests
```

Existing product suites at `test/features/products/*_test.dart` remain valid;
new tests should follow the mirrored layout. Do not move working tests merely to
rename folders. Test names state observable behavior and expected outcomes.
Use arrange/act/assert, isolated setup and explicit cleanup. Tests should prevent
real regressions rather than duplicate private implementation details.

| Boundary | Approach | Current examples |
| --- | --- | --- |
| Domain | Construct use case with mock repository; invalid inputs never call dependencies; assert exact values, permissions and typed failures | Authentication QR and Home lookup direct unit tests; Products creation, editing, pricing and details suites |
| Repository/data mapping | Mock Dio or controlled datasource/storage; cover JSON-RPC and result failures separately, required/optional fields, no credential leakage, duplicate/conflict and uncertain-write outcomes | `test/core/network/`, auth/home data suites, product repository suites |
| Riverpod | Fresh `ProviderContainer.test()`, override repository/service providers; listen to auto-dispose state for test lifetime; await deterministic futures/completers | Session, lookup, creation, edit, price and details controller suites |
| Widgets | Pump page with `ProviderScope` overrides; assert loading, populated/empty, error, retry where safe, disabled/permission states, submission suppression, small screen and keyboard behavior | Product details/creation/edit/price pages; splash/login/scanner suites |
| Routing | App with controlled auth/repositories/scanner; exercise named routes, auth restoration/expiry, push/pop/replacement and refreshed return state | `test/app_test.dart`, product navigation and scanner-return tests |
| Device integration | Run manually on an emulator or device; controlled journeys use fake cameras/repositories and physical-camera tests are separate | `integration_test/app_test.dart`; `scanner_return_test.dart` is device-only |

Domain code remains independent of Flutter, Riverpod, Dio and API payloads.
The Flutter test runner can run these Dart domain tests without changing that
production dependency rule. Use existing mocktail for interaction checks and
handwritten fakes for multi-step behavior. Fixtures must be synthetic; never copy
real tokens or QR challenges into a test or snapshot.

Control clocks through `utcNowProvider`; use completers for asynchronous states.
Do not add arbitrary sleeps to unit/widget tests. Keep pending operations and
subscriptions cleaned up, invalidate/close containers as appropriate, and assert
late async results cannot mutate a disposed or replaced session. Do not share
containers, mutable fakes or saved auth between test cases.

Widget tests use the real shared theme, stable keys/semantics and relevant screen
sizes. Prefer state/interaction assertions to fragile pixel snapshots. Visual
exports assist design review; they do not replace functional assertions. Native
permissions and optical recognition require separate physical-device evidence.

## Commands and CI

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter test --coverage
flutter test test/features/home/domain/use_cases/lookup_product_test.dart
```

`quality.yaml` runs on every branch push, every pull request, main merge-queue
checks and manual dispatch. A PR merge is also a push to main. It checks format,
analysis, all unit/widget tests with LCOV artifact and Fastlane Ruby syntax. Emulator/device integration jobs are deliberately excluded from CI; keep `integration_test/` for manual verification. No signing/distribution secret is used here.

`license_check.yaml` validates Flutter runtime/dev/transitive dependency licenses
on pushes, PRs to main and merge-queue runs, with retrieval failures treated as
failures. Ruby dependencies and bundled artwork still need their own release
license review. No package is silently exempted.

Require the quality check in the main branch ruleset. If previously required, remove the old `integration (development)`, `integration (staging)` and `integration (production)` checks from that ruleset so removed jobs do not block merging. Mark
Android/unsigned iOS checks required as appropriate. Repository files cannot
configure GitHub branch protection by themselves. Coverage is an artifact for
review; there is no invented percentage threshold or exclusion to inflate it.
A new feature must test its changed domain rules, repository contract, important
provider transitions and user-visible states before merge. Add focused regression
tests for a bug, then run the full suite when cross-feature behavior changes.

See [deployment](deployment.md) for TestFlight and physical iPhone verification.


Validation: the existing suites plus the new direct authentication and lookup
use-case tests produced 348 passing Flutter tests with coverage on 2026-10-19.
