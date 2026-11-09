# Configurable Bootstrap and Hybrid Architecture — analysis and plan

Status: analysis only. No application or addon code was changed.
Analysed: app branch `feature/backend-feature-flags` (`4234e54`, app
`1.1.0+35`) and the addons `mupi_mobile_auth` 19.0.2.0.2 and
`mupi_mobile_pos_api` 19.0.2.1.0 (Mobile API `1.0.0`,
`custom_addons/mupi_mobile_auth/doc/openapi.yaml`).

Terms used here:
- **Configurable Bootstrap** — an explicit, ordered startup sequence whose
  steps, deadlines and failure rules are declared per startup mode (real
  session, Demo Mode, development diagnostics) instead of being implied by
  the provider graph.
- **Capability Manager** — one session-scoped owner of what the signed-in
  shop's backend supports (`GET /meta`) and what the user may do
  (permissions).
- **Feature Resolver** — a pure function that turns capabilities,
  permissions and connectivity into one answer per app feature.
- **Hybrid Architecture** — one codebase that serves different backends by
  choosing, at app composition, the API contract adapter and the workflow
  variant each backend supports, without duplicating pages.

## 1. Current startup flow (AC 1)

```
main_<flavor>.dart → bootstrap(AppEnvironment)
  1. WidgetsFlutterBinding, native flavor check  → ConfigurationErrorApp on mismatch
  2. ApplicationSettings.fromBuild (validated)    → ConfigurationErrorApp on error
  3. AppLogger, Crashlytics reporter (no-op fallback), global error hooks
  4. runApp(ProviderScope(overrides: settings, logger, reporter, read cache,
     repositories, authenticatedMobileApiOverride, backendFeaturesOverride …))
App → routerProvider (initialLocation '/startup' → SplashPage)
  5. sessionControllerProvider.build() → OdooAuthRepository.restore()
     (15 s deadline, ≤ 2 s storage cleanup, GET /auth/session validation)
  6. authenticationRedirect → '/home' or '/login'
  7. Lazily, when a screen needs it: backendFeaturesProvider → GET /meta
     (once per session, keepAlive; failure → BackendFeatures.baseline, unconfirmed)
```

Findings:
- Steps 1–4 are an explicit, well-guarded **platform bootstrap**
  (`lib/bootstrap.dart`). It is already configurable per flavor through
  `ApplicationSettings` and needs no rework.
- Steps 5–7 are an **implicit application bootstrap**. The order comes from
  which provider is watched first. Backend compatibility is never checked
  during startup; it is read lazily by the first screen that asks
  (currently only Update Stock).
- Startup modes exist but are scattered:
  - Demo Mode: `demoLoginProvider` checks in the router, repositories and
    `backendFeaturesOverride`;
  - development diagnostics: `developmentDiagnosticsProvider` and the
    initialization route.

## 2. Authentication, session and routing (AC 2)

| Area | Implementation | Assessment |
|---|---|---|
| QR login | `LoginQrModel.parse` accepts only QR `v: 2`, `type: orangeone.pos-login`; v1 QR → "outdated" message; `api_base` checked by `ApiConfiguration.validateApiBase` | Good. A precedent for contract-version gating at the entry point |
| Exchange | `OdooAuthRepository.signIn` → `POST /auth/qr-exchange` (server enforces `min_app_version` here and on `/meta`) | Upgrade refusal arrives as `FailureKind.upgradeRequired`, shown only as a login error |
| Session state | `SessionController` (container-lived `AsyncNotifier`), generation guards, expiry timer, single-flight token refresh, sign-out on rejected refresh | Reuse unchanged |
| Restore | Strict: 15 s deadline, `/auth/session` must succeed, otherwise storage cleared | Reuse unchanged; compatibility must not extend this deadline |
| Session entity | `AuthSession`: token, `apiBase`, expiry, ids. **No permissions**, although `/auth/session` and the token grant return them | Gap: permissions are re-read in `ProductCatalogRemoteDataSource` and per product (`Product.permissions`) |
| Routing | `routerProvider` (GoRouter, named routes, `refreshListenable` on session + demo login), pure `authenticationRedirect` with a hard-coded `known` path set | Reuse. Redirect knows only "signed in / not signed in / loading"; no state for "app too old", "backend unsupported" or "maintenance" |
| Feature gating | `BackendFeatures` (`lib/core/network/backend_features.dart`), `backendFeaturesOverride` (`lib/app/providers/product_dependencies.dart`), used only in `product_stock_update_page.dart` | Correct pattern, but scattered checks will not scale |

## 3. Odoo addon endpoints and `/meta` (AC 3)

Endpoints (`/api/orangeone/mobile/v1`):
- **`mupi_mobile_auth`:** `GET /meta`, `POST /auth/qr-challenges` (POS UI
  only), `POST /auth/qr-exchange`, `POST /auth/token/refresh`,
  `POST /auth/logout`, `GET /auth/session`, `POST /telemetry/events`, and a
  JSON 404 catch-all for unknown paths.
- **`mupi_mobile_pos_api`:** products (by barcode, search, create, read,
  patch, price), stock adjustments and movements, history, changes, taxes,
  categories.

`GET /meta` (public, no token, `check_app_version=True`):

| Field | Current app use | Should be used for |
|---|---|---|
| `api_version` (`1.0.0`) | Stored in `BackendFeatures.apiVersion`, never evaluated | Contract selection; "backend too old / too new" |
| `min_app_version` | Not read; the server answers `APP_UPGRADE_REQUIRED` (426) | Upgrade screen before login |
| `latest_app_version` (optional) | Not read | Dismissible "update available" notice |
| `features` | Read; gates stock Add/Remove | Capability Manager input |
| `supported_locales` | Not read | Optional: hide languages the shop cannot translate |
| `server_time` | Not read | Optional: clock-skew diagnostics |
| `maintenance` | Not read; `MAINTENANCE` maps to `FailureKind.network` | Dedicated maintenance state |

Today's addon features: `telemetry`, `stock_adjustments`, `stock_movements`,
`categories`, `category_create`, `product_history`, `product_changes`,
`product_search`. App baseline (oldest supported addon 19.0.2.0.0): all of
them except `stock_movements` and `telemetry`.

**Permissions are not in `/meta`.** They are per user (`/auth/session`,
token grant `session.permissions`) and per product (`Product.permissions`).
A shop with an addon older than v2 has no `/meta`: it answers 404 or
something other than the JSON envelope. The app currently falls back to the
baseline silently and fails later on real calls.

No addon change is required for this plan: everything the app needs is
already in the contract.

## 4. Reusable components (AC 4)

| Component | File | Reuse as |
|---|---|---|
| Platform bootstrap | `lib/bootstrap.dart` | Stage 0, unchanged |
| Build settings, environment | `core/config/application_settings.dart`, `app_environment.dart`, `environment_loader.dart` | Bootstrap plan selection (flavor, diagnostics) |
| Origin and API base validation | `core/config/api_configuration.dart` | Pre-login `/meta` call against the QR `api_base` |
| App version | `core/config/app_version.dart` | Compatibility comparisons |
| API client | `core/network/mobile_api_client.dart` (envelope, error-code mapping, `X-App-Version`) | Unchanged; extended mapping (§5) |
| Feature detection | `core/network/backend_features.dart`, `backendFeaturesOverride` | Becomes the Capability Manager's backend source |
| Session | `SessionController`, `OdooAuthRepository`, `SecretStore` | Unchanged; the bootstrap orchestrates them, never re-implements them |
| QR contract check | `LoginQrModel` | Unchanged; the pre-login `/meta` step follows it |
| Product permissions | `core/network/product_payload.dart`, `product_access_model.dart` | Per-product input to the Feature Resolver |
| Demo Mode | `features/demo/*`, chosen in `product_dependencies.dart` | The existing hybrid precedent (alternative repositories chosen in composition) |
| Router | `app/router/app_router.dart`, `auth_redirect.dart` | Extended with a pure compatibility redirect |
| Errors, logging, Crashlytics | `core/errors/app_failure.dart`, `core/logging/app_logger.dart`, `core/monitoring/*` | New fixed `LogEvent` values only |
| External launcher | `core/platform/external_launcher.dart` | Store link on the upgrade screen |
| Splash | `SplashPage`, `/startup` | Shown while bootstrap stages run |

## 5. Required changes for Configurable Bootstrap (AC 5)

1. **`BootstrapPlan`** (new, `lib/app/bootstrap/`): an ordered list of
   stages, each with an id, a deadline and a failure rule (`fatal`,
   `degrade`, `skip`). Three plans are chosen from `ApplicationSettings` and
   Demo Mode; no remote configuration:
   - **Real session:** restore → backend compatibility → capabilities → route.
   - **Demo Mode:** demo capabilities → route. No network, storage or
     Crashlytics identity, as `docs/demo-mode.md` requires.
   - **Development diagnostics:** the real-session plan plus the existing
     diagnostics route.
2. **`BootstrapController`** (new `AsyncNotifier`, container-lived): runs
   the plan after `runApp` and exposes `BootstrapState`
   (`running(stage)`, `ready`, `blocked(reason)`). Rules:
   - it **calls** `SessionController`; it never duplicates restore logic;
   - the 15 s restore deadline and 2 s cleanup rule stay inside
     `OdooAuthRepository`;
   - the compatibility stage has its own short deadline and the `degrade`
     rule (baseline, unconfirmed). It **never signs out** and never clears
     storage.
3. **Compatibility status** (new model): `compatible`, `appUpgradeRequired`,
   `backendUnsupported`, `maintenance(until)`, `unknown`.
4. **Error mapping:**
   - add `FailureKind.maintenance` (today `MAINTENANCE` → `network`);
   - update the exhaustive switches, such as
     `core/monitoring/reportable_failure.dart`.
5. **Router:**
   - a pure `compatibilityRedirect`, evaluated after `authenticationRedirect`;
   - new routes `/upgrade`, `/backend-unsupported`, `/maintenance`, added to
     the `known` set;
   - `refreshListenable` also listens to the bootstrap and capability state.
6. **Pre-login check:** after the QR is parsed and before
   `/auth/qr-exchange`, call `GET {api_base}/meta`:
   - 426 → upgrade screen;
   - no `/meta` envelope → backend unsupported;
   - `maintenance` set → maintenance screen;
   - otherwise continue, and hand the result to the Capability Manager so
     it is not read twice.
7. **UX:** upgrade screen with a store link; dismissible notice for
   `latest_app_version`; all texts in the six ARB files.
8. **Logging:** fixed `LogEvent` values (`compatibilityResolved`,
   `appUpgradeRequired`, `backendUnsupported`); no URLs or payloads.

## 6. Required changes for Capability Manager and Feature Resolver (AC 6)

**Capability Manager** (`lib/core/capabilities/`, session-scoped, reset on
sign-out and identity change). It replaces `backendFeaturesOverride` and keeps
its behaviour.

- **State:** `BackendCapabilities` = `apiVersion`, `features`, `confirmed`,
  `minAppVersion`, `latestAppVersion`, `maintenance`, `readAt`, plus
  `SessionPermissions`.
- **Sources:**
  - the pre-login `/meta`;
  - `/meta` after a restore;
  - Demo Mode's fixed set;
  - the baseline on failure.
- **Refresh triggers:**
  - sign-in and restore;
  - a screen opening while the features are unconfirmed (existing
    behaviour);
  - a gated endpoint answering 404 `NOT_FOUND`.

  No polling and no re-read on resume.

**Session permissions:**
- add optional `permissions` to `AuthSession`;
- parse them in `SessionModel` from the token grant and `/auth/session`;
- missing keys count as `false`;
- they are kept in memory only, never in the read cache, as
  `encrypted_read_cache.dart` already requires.

**Feature catalog** (`AppFeature` enum). Each entry declares:
- its backend flag;
- the session permissions it needs;
- whether it works offline;
- whether Demo Mode supports it;
- its workflow variants.

| Feature | Flag | Permissions | Offline |
|---|---|---|---|
| Product lookup and details | — (baseline) | `product_read` | read cache |
| Product create | baseline | `product_create`, `product_update_price` | no |
| Edit name, tax, category | baseline | `product_update_name` / `_taxes` / `_category` | no |
| Price update | baseline | `product_update_price` | no |
| Stock update | `stock_adjustments` (+ `stock_movements` for Add/Remove) | `stock_adjust` | no |
| Product history | `product_history` | `product_history_read` | no |
| Discounts (planned) | `product_discounts` | `discount_read`, `discount_manage` | no |

**Feature Resolver:** a pure function, plus one provider
(`featureAvailabilityProvider(AppFeature)`):

```
resolve(feature, capabilities, sessionPermissions, productPermissions?, online)
  → available(variant) | readOnly | disabled(reason) | hidden(reason) | unavailableOffline
```

Screens ask only the resolver. The first migration is the Update Stock
operation selector, keeping today's behaviour exactly; later, the price,
edit and create entry points.

## 7. Hybrid Architecture requirements (AC 7)

Three axes can differ between shops and builds. Each is resolved once, in
app composition, never inside pages.

| Axis | Today | Mechanism |
|---|---|---|
| **Startup flow** | Real session, Demo Mode, diagnostics (scattered checks) | `BootstrapPlan` per mode (§5) |
| **API contract** | One contract: `/api/orangeone/mobile/v1`, API 1.x, QR v2 | `ContractResolver` reads `/meta` `api_version` (major) and selects the adapter set |
| **Workflow** | Stock Update vs Update/Add/Remove, chosen in the page | Workflow variants returned by the Feature Resolver |

Rules:
- **Domain contracts stay single:** `ProductRepository`,
  `ProductDetailsRepository`, `AuthRepository`. Hybrid means several **data
  implementations** behind them — today `Odoo*` (API v1) and `Demo*` — and
  never several pages.
- **Contract adapters:** the composition in `product_dependencies.dart`
  becomes "resolver → adapter set". Only the v1 adapter set exists today. A
  `v2` set is written only if the backend ever publishes a breaking `/v2`
  path; the API is additive, so that should be rare. Do not create
  speculative v2 classes now (AGENTS.md: no speculative integrations).
- **Unsupported contract:**
  - an `api_version` major the app does not know → backend unsupported, or
    "update the app" if it is newer;
  - an older contract (no `/meta`) → backend unsupported.
- **Workflow variants** are enums the page switches on, for example
  `StockWorkflow.countOnly | countAddRemove` or
  `DiscountWorkflow.none | readOnly | manage`. The data layer chooses
  endpoints by variant, and pages share widgets.
- **Additive models:** API models keep ignoring unknown fields; new fields
  are optional in the domain (for example a future `imageUrl`).

## 8. Implementation plan (AC 8)

Each phase is releasable on its own, keeps the current behaviour and ends
with:

```
dart format lib test integration_test
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

| Phase | Work | Behaviour change | Key tests |
|---|---|---|---|
| 0 | Characterisation tests of today's startup, restore deadlines, redirects, Demo Mode and stock gating | None | Pin current results before refactoring |
| 1 | Feature catalog, Feature Resolver, Capability Manager wrapping `BackendFeatures`; migrate the stock selector | None | Resolver table tests; two offline/recovery cycles with mounted listeners (AGENTS.md rule) |
| 2 | Session permissions in `AuthSession` / `SessionModel`; the resolver uses them | Entry points may be disabled where the backend already refused (403) | Model parsing with and without keys; never cached |
| 3 | `BootstrapPlan`, `BootstrapController`, compatibility status, `FailureKind.maintenance`, compatibility redirect and the three screens | New screens only for upgrade, unsupported backend and maintenance | Plan per mode; deadlines; `/meta` failure degrades, never signs out; no redirect loops |
| 4 | Pre-login `/meta` in the QR flow; `latest_app_version` notice | Clear messages before login | 426, 404 or non-envelope, maintenance, success; Demo Mode makes no request |
| 5 | `ContractResolver` seam (v1 only) and workflow variants; discounts as the first new consumer | None until a new flagged feature ships | Old addon (no flag) vs new addon; unknown `api_version` major |

Review against existing rules (checked for each phase):
- `ProviderScope` once; manual Riverpod 3 providers; `<feature>ControllerProvider` naming.
- Startup stays strict: the restore and cleanup deadlines are untouched;
  compatibility failures degrade and never clear storage.
- Demo Mode never touches the real session, Dio, secure storage, the cache
  or Crashlytics identity.
- No permissions, versions or tokens in the read cache.
- Fixed `LogEvent` values only; Crashlytics allowlist unchanged.
- Features do not import each other; composition stays in `lib/app`.
- No new packages are needed.

## 9. Risks

- **Over-engineering:** keep the bootstrap a short list of stages in plain
  Dart. No plugin system, no remote configuration (out of scope per
  AGENTS.md).
- **Startup latency:** the compatibility stage runs after restore with its
  own short deadline. On failure it degrades to the baseline; it never
  blocks the home screen.
- **Redirect loops:** keep both redirects pure and table-tested, and keep
  the `known` path set in one place.
- **Stale capabilities:** an addon upgraded or uninstalled during a session
  is caught by the 404-triggered refresh and the next sign-in.
- **Pre-v2 shops:** they now see "backend unsupported" before login instead
  of failing later. This is a deliberate, documented change of message.

## 10. Decisions for review

1. Should "backend unsupported" block sign-in, or allow a limited mode? The
   proposal: block, because no v1 endpoints exist on pre-v2 addons.
2. Should session permissions disable entry points before a write
   (phase 2)? The proposal: yes, matching the server's answer.
3. Should `/meta` be re-read on resume after a long background period? The
   proposal: no (AGENTS.md: no revalidation on ordinary resume); the
   404-triggered refresh is enough.
