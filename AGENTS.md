# OrangePOS — Codex Repository Instructions

## Mission
Build and maintain **OrangePOS**, a Flutter Android/iOS mobile inventory application backed by Odoo. Implement the user's requested task only, with reliable, maintainable, testable code. Treat this file as standing repository guidance, not permission to implement the whole backlog.

## Sources of truth (priority)
1. The current user task and its acceptance criteria.
2. Existing repository code, tests, configuration, and documentation.
3. Confirmed Odoo backend controller code and contract tests (see API section).
4. OrangeONE Mobile Design System Figma: https://www.figma.com/design/r6TjxFouED6tJ9fX6evjhz/OrangeONE---Mobile-Design-System?node-id=0-1
5. This document for cross-cutting implementation conventions.

Do not guess Figma properties or backend behavior when their source is unavailable. State what is unverified; avoid speculative integrations. Do not introduce new frameworks, dependencies, architecture patterns, or broad refactors without a task-specific reason.

## Before implementing any task
- Inspect the existing repository tree, `pubspec.yaml`, entry points, flavors, relevant feature, tests, and nearby conventions. Respect any more-specific nested `AGENTS.md`.
- Read the task's **Description**, **Goal**, and **Acceptance Criteria**; translate them into a small, scoped implementation plan.
- Identify dependencies and existing work before adding files. Extend working implementations instead of duplicating them.
- Check whether Figma access or the Odoo API contract is required. If inaccessible, do not claim verified fidelity or fabricate fields/endpoints.
- Do not overwrite uncommitted user changes. Avoid changing unrelated files, generated output, lockfiles, native project files, or CI workflows without necessity.

## Flutter project standards
- Flutter/Dart project initialized using Very Good CLI (preserve its existing bootstrap and flavor conventions).
- Support `development`, `staging`, and `production`; keep flavor entry points and configuration consistent with the actual project.
- Use null-safe Dart, idiomatic Flutter, small cohesive classes, and descriptive names.
- Follow existing lints and formatting; use `dart format`, `flutter analyze`, and `flutter test` as applicable. After the final Dart edit (including lint fixes), run `dart format lib test integration_test`, then the exact CI gate `dart format --output=none --set-exit-if-changed lib test integration_test` and require zero changed files before handoff. Never append whitespace after that verification. Keep the staged-content formatting hook and Dart format-on-save settings.
- Avoid `print`; use the established structured logger, excluding credentials, tokens, session identifiers, raw QR payloads, and personally sensitive data.
- Do not hardcode URLs, environment secrets, auth credentials, or deployment credentials in source code.
- Favor existing packages and patterns over adding dependencies. Explain any essential new dependency.



## Riverpod conventions
- Initialize `ProviderScope` once at the application root.
- Use Riverpod for state management and injecting repositories, clients, storage, and other services.
- Prefer the project's existing Riverpod version and provider conventions; do not mix incompatible APIs.
- Keep async/loading/success/empty/failure states explicit. Prevent duplicate submissions and handle disposal/cancellation as appropriate.
- Avoid business logic in `build` methods. Use `ref.watch` for reactive dependencies and `ref.read` for actions where appropriate.
- Keep providers overrideable and test them with controlled dependencies; document new provider naming/lifecycle conventions when introduced.
- Follow `docs/state-management.md`: manual Riverpod 3 providers, `<feature>ControllerProvider` / `<Feature>Controller`, named providers, auto-dispose feature state and container-lived shared dependencies.
- The diagnostic initialization uses local `EnvironmentLoader`; authentication uses a container-lived SessionController, injected AuthRepository and shared Dio/SecretStore. Read `docs/authentication.md` for the confirmed contract and security policy.
- Use fresh `ProviderContainer.test()` instances and service overrides in provider tests; listen to auto-dispose state while testing it. Attach resource cleanup/cancellation through `ref.onDispose` and handle async disposal/stale results.

## Feature-first layer structure (Task 02)
- Use `features/<feature>/presentation/{pages,widgets,providers}`, `domain/{entities,repositories,use_cases}`, and `data/{models,data_sources,repositories}`.
- Domain depends on Dart and domain contracts only; keep Flutter, Riverpod, API payloads and storage details outside it.
- Pages/widgets must not import data implementations or perform API/storage calls. Dispatch actions through feature providers and domain operations.
- Providers may bind data implementations to domain contracts for dependency injection; keep construction separate from UI state logic.
- Core contains reusable non-UI infrastructure; shared contains feature-independent UI. Neither may depend on feature implementations or app composition.
- Features must not import another feature's data or presentation internals. App owns routing and cross-feature composition.
- Empty structure directories may use `.gitkeep`; do not invent business features or placeholder classes. See `docs/architecture.md` for ownership and test conventions.

## Odoo integration: Mobile API v2 contract
The app uses only the OrangeONE Mobile API v2 (`/api/orangeone/mobile/v1`) of the Odoo addons `mupi_mobile_auth` and `mupi_mobile_pos_api` (Orange-POS/odoo_addons PR #192). The source of truth is `custom_addons/mupi_mobile_auth/doc/openapi.yaml` in that repository plus the addon controllers and tests. Read `docs/mobile-api-v2.md` for endpoints, headers and error mapping. The legacy JSON-RPC routes (`/mupi/mobile/...`) were removed; do not reintroduce them.
- Use `MobileApiClient` through `authenticatedMobileApiProvider` (shared `dioProvider`); keep envelopes, payload validation and Odoo-specific models in the data/network layers.
- Branch on `error.code`, never on server message text. Distinguish transport failures, unexpected envelopes (protocol) and API error codes.
- Updates send `If-Match` with the JSON product `version` of a freshly verified read, never the ETag; the ETag is only for `If-None-Match`. Never retry or overwrite after `VERSION_CONFLICT` (412).
- Every write sends an `Idempotency-Key` (`IdempotencyKeys`): new per intent, reused only for the identical request after an uncertain outcome.
- Base URL comes from the QR `api_base`, checked against the flavor's trusted origin; keep timeouts and nonsecret configuration flavor-aware.
- Map API models to domain entities, handling optional/missing values safely. Decimal amounts are strings in the contract.
- Sanitize all request/response logging; never log bearer tokens, session identifiers, secrets, QR payloads or raw authorization headers.
- Do not substitute generic Odoo endpoints or invent fields or stock semantics that the contract does not define.

## Authentication and navigation
- Restore a saved session once on a full restart, with a 15-second validation deadline and cancellation, plus at most 2 seconds for secure-storage cleanup. Stalled cleanup must show a safe storage error and block new login until deletion finishes; never claim storage was cleared before success. Failed/offline validation clears secure storage for fresh QR login; do not poll or revalidate on ordinary resume. Task 13 supersedes runtime outage sign-out for product operations: an already verified session may use encrypted, stale read-only cache until expiry; cache misses remain errors and all offline writes stay disabled. Startup remains strict. Backend auth rejection/expiry/logout still resets session-dependent state. Keep Logout visible on Home. Preserve backend expiry and permission checks.
- QR-based login uses the confirmed QR payload format and backend authentication process. Validate unsupported/expired data and suppress concurrent scan/login requests.
- The login screen offers English, Dutch, French, Italian, Turkish and Tamil through the Very Good CLI localization (`docs/localization.md`); keep texts in `lib/l10n/arb` and the selection persisted. The QR scanner runs its camera only on Wi-Fi (`wifiConnectionProvider`); Wi-Fi never proves the POS network, so do not claim verification.
- Store secrets or session identifiers in platform secure storage through an injectable abstraction, never plain-text preferences.
- Restore valid sessions at startup, clear secrets on logout, and handle expiration without leaking authenticated UI.
- Centralize navigation with GoRouter: named routes, route parameters/results, nested navigation only where needed, and unknown-route fallback.
- Keep authentication redirects separate from route construction; avoid redirect loops and protected-route back-navigation bypasses.
- Implement guards only in tasks where session management and the guard behavior are in scope.

## Inventory workflows
- Unknown-barcode creation belongs to Products and uses `POST /products` (never upserts). Recheck permissions (`product_create`, `product_update_price`), barcode and tax options before writing, require explicit tax selection (`tax_ids: []` is No Tax), and block repeat writes after uncertain outcomes until an explicit barcode check.
- Stock management at the POS stock location only, requiring `stock_adjust` and `stock.adjustable`, never handling lots, packages or owner-specific stock: *Update* sets an absolute counted quantity (`POST /products/{id}/stock-adjustments`); *Add* and *Remove* change the stock by a quantity above zero (`POST /products/{id}/stock-movements`, `operation: add|remove`). The Update Stock screen (`docs/product-stock-update.md`) has the Update/Add/Remove selector (Update default), a live preview (`150 + 40 = 190 Units`) that is never authoritative (the backend reply is), validation before enabling the action (above zero; Remove not above the stock), per-mode label/helper/button, and sends `If-Match` plus a fresh-per-intent `Idempotency-Key` for all three.
- Supported flows: home, barcode scan, product lookup, product details, add/edit product, stock adjustment, and price update.
- The barcode scanner's "Last scanned" card shows only the latest found product (name, Category and Barcode badges, stock, `CHF` price right-aligned; "No Category" when missing); each scan replaces it, the stored history of five is unchanged, and tapping the card repeats the normal lookup. It is session-scoped, kept across product writes, deleted at logout and never blocks scanning. Home and the scanner are localized; do not reintroduce the "Powered By" footer on Barcode Home.
- Treat successful scanner reads as input, not authorization to mutate inventory. Handle permission denial, cancellation, repeated reads, and invalid formats.
- Validate forms and quantities/prices; use correct currency precision and confirmed Odoo pricing/stock rules.
- Require user confirmation for stock and price changes. Block duplicate writes and show success only after backend confirmation.
- Check actual user permissions and backend responses before enabling or completing restricted actions.
- Refresh product details after successful mutations; preserve entered form data after recoverable errors.
- Keep offline reads visibly distinguishable from fresh server data. Do not queue offline writes unless explicitly supported by confirmed backend rules.

## Figma and reusable UI
- All product screens must use `ProductScaffold`, `ProductNavbar`, and `ProductNameCard` for the header/name section. `ProductScaffold` alone paints `OrangeTheme.gradient` across that section; navigation and the shared name card stay transparent so the gradient never restarts at their boundaries. Do not add per-card/header gradients or local orange fills. Keep the card border, white enabled edit icons and barcode text, and permission-disabled states. White form panels fill the remaining content, and sticky action surfaces retain neutral white/glass backing. New product screens must follow this shared composition.
- Use `OrangeTheme.gradient` as the single orange fill for branded backgrounds, headers and product-name cards. This gradient matches the splash (#BE4602 to #FF8A33, shared direction/stops). Sticky action-card backing is clear neutral glass, never the orange gradient. Keep glass highlights untinted. Buttons follow the supplied solid-color component: primary normal/loading/Done #F56600 with white text/icons, pressed/hover #C84E00, disabled #DADCE0 with #5F6368 labels. Outlined buttons use white fill with matching orange text/border, pressed #C84E00, disabled gray text/border. Centralize these in OrangeTheme; no gradients, scrims or text halos on buttons. Keep 12px corners and at least 56px management touch targets. Busy actions stay orange while duplicate taps remain blocked. Use shared palette endpoints for small readable accents; do not invent local orange shades. Regenerate native launch backgrounds with `flutter test tool/generate_brand_background_test.dart` after changing the gradient. Android 12's OS splash accepts only the matching solid endpoint before the gradient handoff.
- Application branding uses `shared/widgets/app_logo.dart` and `assets/branding/app_logo.png`. Keep the supplied artwork untinted. Run `tool/sync_branding.ps1` after updating it and rebuild native launch resources; functional discount/tag icons are separate from branding.
- Product Details has no back arrow or "Powered By" footer; the Open Scanner button returns to the scanner, and its name card shows the Category badge (same `InfoBadge` design, "No Category" fallback) left of the stock badge. Product Details is fully localized.
- Edit Name & Tax, Update Price and Update Stock share the Product Details glass hero card (`detailsLayout`; `showActions: false` on the editing screens): Category pill, name, reference, Stock pill, Tax row (`taxText`) and Barcode row, with blur and a thin white edge over the scaffold gradient (no new colors); Creation shows no name card. The navigation bar shows the cloud (`ProductSyncNavButton`) instead of the pencil and the name card has no cloud. Percent taxes show once (`15%`).
- All four forms: Save Changes (Update Stock shows *Update Stock* / *Add Stock* / *Remove Stock* by mode) → confirmation popup → send only after Confirm → on success return to Product Details with the success toast (`productSuccessProvider`, `ProductSuccessToast`) above Open Scanner; on failure stay on the form with an error and never show success. A success toast names only the fields actually changed and saved (`editSuccessText`, `ProductEditState.savedFields`), never unchanged ones. Creation requires name, tax (backend `default_tax_ids` when not chosen; never hardcode a tax) and category (select or create via `POST /categories`, `category_create`); price (empty = 0.00) and stock are optional, an empty stock is *Not Set*, never zero.
- Never name the backend product in user-visible text and show "Powered By" on the Login Home screen only (`test/app/no_vendor_names_test.dart`).
- Every product-name card on every screen must include the reusable stock badge with the current backend quantity/unit. This includes price update and future product screens. Unknown stock must be labelled unavailable, never fabricated.
- Sticky action surfaces use 12 logical pixel top corners and clear, neutral glass (blur with translucent white highlights); do not add warm or other colored tints to the glass. Keep the action buttons' specified brand colors.
- Keep primary management actions sticky at the bottom of action-heavy screens, with fixed header navigation and independently scrolling middle content. Use large full-width touch targets (at least 56 logical pixels high), safe-area spacing, and a restrained glossy/frosted surface with strong text contrast and subtle separation. Reserve layout space so the bar never hides content; use a side-by-side arrangement on wide/short screens when appropriate. Preserve permission/disabled states. Follow this convention for future screens unless the user or supplied design explicitly requests otherwise.
- Keep screen header navigation fixed outside scrolling content by default: back, title and header actions remain visible while the page scrolls. Follow this convention for future screens unless the user or supplied design explicitly requests a different behavior. Preserve safe-area spacing and pull-to-refresh for body content.
- Treat Figma as the authoritative visual reference when a task asks for a designed screen. Access the specified page/node before implementing when available.
- Respect design tokens, color, typography, spacing, components, states, assets, and responsive behavior; do not invent design fidelity if the link cannot be inspected.
- Translate screens into feature `pages/` plus focused, reusable `widgets/`. Move only genuinely cross-feature components to `shared/`.
- Include accessibility semantics, clear empty/loading/error states, touch targets, and safe-area/keyboard behavior.
- Keep UI responsive across supported phone sizes and avoid hardcoded pixel assumptions.

## Application environments and logging (Task 11)
- Read `docs/environments-and-logging.md`. Bootstrap validates native flavor and `ApplicationSettings` once, then injects them. Use matching nonsecret config templates; do not silently default malformed settings or change QR-selected POS origins.
- Use `appLoggerProvider` and fixed `LogEvent` values; never add raw message/error/stack/body/header/URL/QR fields. Production and nondebug builds must emit no development logs. Diagnostics routes are development-debug only and default closed.

## Error handling and observability
- Translate network, backend, auth/authorization, validation, and unexpected errors into typed application failures.
- Show safe, actionable user-facing messages; do not display server traces or sensitive internals.
- Retry only operations known to be safe/idempotent or explicitly guarded against duplication.
- Initialize Firebase Crashlytics and Remote Config only for tasks where they are in scope; isolate environment settings, supply safe defaults, and exclude sensitive values from telemetry.

## Testing CI (Task 11)
- Read `docs/testing.md`. `.github/workflows/flutter_tests.yml` replaces only the quality workflow: format, analysis, offline unit/widget tests, coverage and deployment-script checks once per commit (push only on `main`/`develop`/`staging`, PRs otherwise), merge queues and manual dispatch; actionlint and `tool/ci/test_workflows.py` / `test_versioning.py` guard triggers, secrets and the `pubspec.yaml` version, which must stay above every uploaded TestFlight build (`tool/ci/release_versions.json`).
- Native checks in `android.yaml` and `ios.yaml` cover all three flavors; preserve `license_check.yaml`. Distribution is manual from main through protected `ios-production` / `ios-app-store` environments. Compile candidate source without secrets, then validate/sign/export on a fresh trusted runner without rebuilding. Preserve regression tests in `tool/ci`, cleanup on partial failure and explicit iPhone confirmation before submission. Never automatically publish. Read `docs/deployment.md`.
- Preserve existing test suites and use mirrored feature/layer folders for new suites. Reuse Mocktail, service overrides and controlled fakes; no live Odoo or credential dependencies.

## Tests and definition of done
- Emulator/device integration tests are manual only; do not add integration jobs to CI unless the user requests it. Keep CI unit/widget tests, coverage, format and analysis checks. Preserve integration test files for local/device use.
For changed behavior, add/update focused tests where practical:
- Domain use cases and mapping: unit tests.
- Data repositories: mocked Dio/data-source/secure-storage dependencies.
- Riverpod providers: overrides and deterministic async state transitions.
- Flutter pages: widget tests for loading, success, empty, errors, and interactions.
- GoRouter and major journeys: navigation/integration tests with controlled backends and scanner abstractions.
- Do not let tests call live production Odoo, depend on a physical camera in CI, or modify real inventory records.

Run checks appropriate to the touched area (when tools are installed):
```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```
Use repository-specific flavor/build commands rather than assuming entry-point names. Task 12 native workflows are separate from Flutter testing CI; verify actual signing/upload and device results before claiming success. Never commit keys or certificates.

## Scope, quality, and handoff rules
- Implement only requested acceptance criteria; identify blockers or prerequisites instead of silently expanding scope.
- Keep changes small and reviewable; do not suppress lints, hide errors with broad catches, or change public APIs casually.
- Never commit secret files, credentials, tokens, private certificates, provisioning profiles, or generated sensitive files.
- Update README/config examples when commands, setup, environment requirements, or CI behavior change.
- Before finishing, summarize: files changed, behavior implemented, acceptance criteria satisfied, verification commands/results, and any unverified items or follow-up dependencies.
- Be accurate: do not claim iOS builds, physical-device camera flows, backend calls, or Figma matching were tested unless actually verified.

## Offline product reads (Task 13)
- Read `docs/offline-data.md`. Use Drift for encrypted, approved read snapshots only (schema 2), scoped to environment/backend/company/user/session family, never tokens, with 24-hour retention and bounded storage. Never cache permissions, versions, authentication payloads or offline writes. Refresh cached products from `GET /products/changes` on cache open and recovery; a definitive auth rejection there (`TOKEN_REVOKED`/`TOKEN_INVALID`) signs the session out through the identity-guarded handler.
- Keep startup validation strict. Preserve read-only access only during an already verified open session; purge session cache on logout/disposal and never fall back on auth/permission rejection.
- Every product screen shows the shared accessible sync indicator: Product Details places it in the fixed navigation header; other product screens keep it opposite the logo in `ProductNameCard`. Connectivity is a hint; only authoritative reads restore online status. Preserve drafts during recovery and never replay writes.

- Riverpod stream notifications must carry changing values (such as monotonic integer revisions), not repeated void/null payloads. Regression tests must cover at least two offline/recovery cycles with mounted UI/provider listeners and assert buttons recover.
- Keep creation preflight/validation outside the cache write critical section; guard only the actual save and any tax correction. Test creation with a real EncryptedReadCache as well as without it.
- Cache deserialization/decryption is an untrusted boundary: convert all malformed-envelope/type/authentication failures into a safe typed storage failure and failed sync status. Test both short envelopes and a flipped ciphertext byte.
