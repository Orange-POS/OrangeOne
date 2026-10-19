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
- Follow existing lints and formatting; use `dart format`, `flutter analyze`, and `flutter test` as applicable.
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

## Odoo integration: verify contract before implementation
Use Dio centrally via a Riverpod-provided API client. Backend routes in the supplied `mupi_mobile_pos_api.zip` archive were observed in:
- `mupi_mobile_pos_api/controllers/mobile_pos_api.py`
- `mupi_mobile_auth/controllers/mobile_auth.py`

Observed routes (all HTTP POST with Odoo `type="json"`; inspect source/tests for exact payload, authentication, and response contracts):
- `/mupi/mobile/api/ping`
- `/mupi/mobile/api/products/find`
- `/mupi/mobile/api/products/save`
- `/mupi/mobile/api/products/price/update`
- `/mupi/mobile/api/products/update`
- `/mupi/mobile/api/products/references`
- `/mupi/mobile/api/products/name/update`
- `/mupi/mobile/auth/challenge/create`
- `/mupi/mobile/auth/challenge/validate`
- `/mupi/mobile/auth/token/check`

The archive is a **reference attachment, not necessarily part of the Flutter repository**. Locate the backend source or contract documentation supplied in the current workspace; if absent, request/identify the missing contract rather than inventing JSON fields.
- Keep Odoo-specific models and JSON-RPC envelope handling in the data/network layers.
- Distinguish HTTP/transport failures, JSON-RPC protocol errors, and application-level result failures. Verify the server's actual envelope before parsing.
- Make base URL, timeouts, and nonsecret configuration flavor-aware. Use appropriate request IDs if required by the confirmed protocol.
- Map API models to domain entities, handling optional/missing values safely.
- Sanitize all request/response logging; never log bearer tokens, session identifiers, secrets, or raw authorization headers.
- Do not substitute generic Odoo endpoints or invent stock-write semantics without backend confirmation.

## Authentication and navigation
- Restore a saved session once on a full restart, with a 15-second validation deadline and cancellation, plus at most 2 seconds for secure-storage cleanup. Stalled cleanup must show a safe storage error and block new login until deletion finishes; never claim storage was cleared before success. Failed/offline validation clears secure storage for fresh QR login; do not poll or revalidate on ordinary resume. The first authenticated network/timeout failure signs out and resets session-dependent state without retrying. Keep Logout visible on Home. Preserve backend expiry and permission checks.
- QR-based login uses the confirmed QR payload format and backend authentication process. Validate unsupported/expired data and suppress concurrent scan/login requests.
- Store secrets or session identifiers in platform secure storage through an injectable abstraction, never plain-text preferences.
- Restore valid sessions at startup, clear secrets on logout, and handle expiration without leaking authenticated UI.
- Centralize navigation with GoRouter: named routes, route parameters/results, nested navigation only where needed, and unknown-route fallback.
- Keep authentication redirects separate from route construction; avoid redirect loops and protected-route back-navigation bypasses.
- Implement guards only in tasks where session management and the guard behavior are in scope.

## Inventory workflows
- Unknown-barcode creation belongs to Products. Support the original confirmed `/products/save` contract without requiring new capability fields. When `create_only_supported` is advertised, send `create_only: true`; otherwise send only original parameters and require its exact created acknowledgment. Original upsert races cannot be prevented by client lookup alone. Recheck permissions, barcode and tax options, require explicit tax selection (including No Tax), and block repeat writes after uncertain outcomes until an explicit barcode check.
- Supported flows: home, barcode scan, product lookup, product details, add/edit product, stock adjustment, and price update.
- Treat successful scanner reads as input, not authorization to mutate inventory. Handle permission denial, cancellation, repeated reads, and invalid formats.
- Validate forms and quantities/prices; use correct currency precision and confirmed Odoo pricing/stock rules.
- Require user confirmation for stock and price changes. Block duplicate writes and show success only after backend confirmation.
- Check actual user permissions and backend responses before enabling or completing restricted actions.
- Refresh product details after successful mutations; preserve entered form data after recoverable errors.
- Keep offline reads visibly distinguishable from fresh server data. Do not queue offline writes unless explicitly supported by confirmed backend rules.

## Figma and reusable UI
- Use `OrangeTheme.gradient` as the single orange fill for branded backgrounds, headers and product-name cards. This gradient matches the splash (#BE4602 to #FF8A33, shared direction/stops). Sticky action-card backing is clear neutral glass, never the orange gradient. Keep glass highlights untinted. Buttons follow the supplied solid-color component: primary normal/loading/Done #F56600 with white text/icons, pressed/hover #C84E00, disabled #DADCE0 with #5F6368 labels. Outlined buttons use white fill with matching orange text/border, pressed #C84E00, disabled gray text/border. Centralize these in OrangeTheme; no gradients, scrims or text halos on buttons. Keep 12px corners and at least 56px management touch targets. Busy actions stay orange while duplicate taps remain blocked. Use shared palette endpoints for small readable accents; do not invent local orange shades. Regenerate native launch backgrounds with `flutter test tool/generate_brand_background_test.dart` after changing the gradient. Android 12's OS splash accepts only the matching solid endpoint before the gradient handoff.
- Application branding uses `shared/widgets/app_logo.dart` and `assets/branding/app_logo.png`. Keep the supplied artwork untinted. Run `tool/sync_branding.ps1` after updating it and rebuild native launch resources; functional discount/tag icons are separate from branding.
- Every product-name card on every screen must include the reusable stock badge with the current backend quantity/unit. This includes price update and future product screens. Unknown stock must be labelled unavailable, never fabricated.
- Sticky action surfaces use 12 logical pixel top corners and clear, neutral glass (blur with translucent white highlights); do not add warm or other colored tints to the glass. Keep the action buttons' specified brand colors.
- Keep primary management actions sticky at the bottom of action-heavy screens, with fixed header navigation and independently scrolling middle content. Use large full-width touch targets (at least 56 logical pixels high), safe-area spacing, and a restrained glossy/frosted surface with strong text contrast and subtle separation. Reserve layout space so the bar never hides content; use a side-by-side arrangement on wide/short screens when appropriate. Preserve permission/disabled states. Follow this convention for future screens unless the user or supplied design explicitly requests otherwise.
- Keep screen header navigation fixed outside scrolling content by default: back, title and header actions remain visible while the page scrolls. Follow this convention for future screens unless the user or supplied design explicitly requests a different behavior. Preserve safe-area spacing and pull-to-refresh for body content.
- Treat Figma as the authoritative visual reference when a task asks for a designed screen. Access the specified page/node before implementing when available.
- Respect design tokens, color, typography, spacing, components, states, assets, and responsive behavior; do not invent design fidelity if the link cannot be inspected.
- Translate screens into feature `pages/` plus focused, reusable `widgets/`. Move only genuinely cross-feature components to `shared/`.
- Include accessibility semantics, clear empty/loading/error states, touch targets, and safe-area/keyboard behavior.
- Keep UI responsive across supported phone sizes and avoid hardcoded pixel assumptions.

## Error handling and observability
- Translate network, backend, auth/authorization, validation, and unexpected errors into typed application failures.
- Show safe, actionable user-facing messages; do not display server traces or sensitive internals.
- Retry only operations known to be safe/idempotent or explicitly guarded against duplication.
- Initialize Firebase Crashlytics and Remote Config only for tasks where they are in scope; isolate environment settings, supply safe defaults, and exclude sensitive values from telemetry.

## Tests and definition of done
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
Use repository-specific flavor/build commands rather than assuming entry-point names. CI should separately validate Android and unsigned iOS builds on a GitHub-hosted macOS runner; signed iOS/TestFlight steps require securely configured signing assets and must never commit keys or certificates.

## Scope, quality, and handoff rules
- Implement only requested acceptance criteria; identify blockers or prerequisites instead of silently expanding scope.
- Keep changes small and reviewable; do not suppress lints, hide errors with broad catches, or change public APIs casually.
- Never commit secret files, credentials, tokens, private certificates, provisioning profiles, or generated sensitive files.
- Update README/config examples when commands, setup, environment requirements, or CI behavior change.
- Before finishing, summarize: files changed, behavior implemented, acceptance criteria satisfied, verification commands/results, and any unverified items or follow-up dependencies.
- Be accurate: do not claim iOS builds, physical-device camera flows, backend calls, or Figma matching were tested unless actually verified.


