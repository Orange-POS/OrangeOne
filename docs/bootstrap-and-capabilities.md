# Configurable bootstrap, capabilities and hybrid architecture

One app version serves shops with different addon versions, contracts,
permissions and workflows. Background and decisions:
[configurable-bootstrap-analysis.md](configurable-bootstrap-analysis.md).

## Startup sequence

```
bootstrap(AppEnvironment)                       lib/bootstrap.dart
  flavor + ApplicationSettings check            → ConfigurationErrorApp on error
  logger, Crashlytics reporter, error hooks
  loadStartupConfiguration (saved sign-in method, ≤ 2 s, never fails)
  runApp(ProviderScope(… savedStartupConfigurationProvider …))
router (initial '/startup' splash)
  SessionController restore (unchanged: 15 s deadline, strict validation)
  Capability Manager: GET /meta right after sign-in or restore
  bootstrapRedirect → compatibility screen | home | the workflow's entry
```

## Configurable bootstrap

### Configuration model

The device saves only what is known before any shop: the **sign-in method**.
Everything customer-specific is discovered per session and never saved, so
a saved profile can never outlive the shop it belonged to.

| Concern | Source | Saved? |
|---|---|---|
| Sign-in method (`AuthenticationMethod`) | Settings → *SIGN-IN* | Yes (device) |
| Customer/backend identity | The signed-in session: QR `api_base` (checked against the flavor's trusted origin), company, user, session family | Only inside the session record |
| API compatibility profile (`ApiContract`) | That shop's `GET /meta` `api_version` | No: read every session |
| Supported workflows / features | That shop's `GET /meta` `features` + session permissions | No |

- **Methods** (`features/startup/domain/entities/startup_workflow.dart`):
  - `qrLogin`: available (POS QR challenge + `POST /auth/qr-exchange`).
  - `oidc`: **not available**. No OrangeONE OIDC contract exists
    (discovery document, client registration, exchange of an identity token
    for a Mobile API token). Nothing is invented; it cannot be selected.
  - `credentials`: username/password, **not OIDC**, **not available**; the
    Mobile API has no credentials endpoint.
- **Storage:** key `orangeone.startup_configuration`, JSON
  `{"schema": 2, "auth_method": "qr_login"}` through the injectable
  `SecretStore` (nonsecret, like the language). Schema 1
  (`orangeone.startup_workflow`, bare value) is migrated once on read and
  then deleted; a failed migration repeats on the next start. An unknown
  schema, method or unreadable value falls back to QR login. A saved method
  that is no longer available runs QR login (`effectiveMethod`).
- **Bootstrap Resolver** (`app/bootstrap/bootstrap_resolver.dart`), a pure
  function used as the GoRouter redirect:
  1. **Compatibility.** A real signed-in session whose shop refused the app
     sees only `/compatibility`. Demo Mode is never blocked. Settings stay
     reachable.
  2. **Authentication.** `authenticationRedirect` decides, unchanged.
  3. **Starting component.** The login entry is
     `startupEntryPath(configuration.effectiveMethod)`.

### Supported combinations

| Backend | Method | Result |
|---|---|---|
| Older addons (Mobile API 1.0, no `product_discounts`) | QR | Supported; discounts hidden |
| Updated addons (1.1) without `mupi_product_discount` | QR | Supported; discounts hidden |
| Updated addons with `mupi_product_discount` | QR | Supported; discounts by permission |
| `api_version` 0.x or unreadable (confirmed) | QR | Blocked: server not supported |
| `api_version` 2.x or newer | QR | Blocked: update required |
| `APP_UPGRADE_REQUIRED` / `MAINTENANCE` | any | Blocked until the shop confirms compatibility |
| Any shop | OIDC | Not selectable until a verified OIDC contract exists |
| Any shop | Username/password | Not selectable (no endpoint) |

**Discovery once a second method exists:** the method must be advertised by
the shop (for example a `GET /meta` list of sign-in methods, or the QR
payload) *and* implemented by this build; otherwise QR login stays. The
backend's minimum app version and every security check still apply to every
method.

### Changing the method (session lifecycle)

`StartupConfigurationController`:
- `select(method)` applies only while signed out (`SessionLifecycle`, bound
  in `app/providers/session_lifecycle_bindings.dart`); while a session
  exists it returns `signOutRequired` and changes nothing. Settings disable
  the choices with a "Sign out to change the sign-in method." hint.
- `switchTo(method)` is the controlled transition: sign out, wait until the
  stored credentials are confirmed deleted, then apply and save. If secure
  storage cannot be cleared it returns `cleanupFailed`, keeps the old method
  and the login stays blocked (existing storage-error behaviour). A newer
  request supersedes an older one (generation guard); a sign-in that starts
  meanwhile is never changed (`signOutRequired`).
- Every session-owned state is bound to the session identity and disposed
  with it: credentials, permissions, `/meta` capabilities, compatibility
  decisions, read cache, recent scans, unset-stock flags, monitoring
  identity and the discount repository. Pending `/meta`, product and
  discount requests are cancelled through their `CancelToken`s; a late
  answer of the old session cannot reach the new one.
- `capabilityScopeProvider` (`<method>|<environment>|<api base>|<company>|`
  `<user>|<session family>`, or the Demo Mode sample) identifies whose
  decisions apply.
- An interrupted switch (app killed while signing out) restarts with the old
  method and no session: QR login.

**Adding a method:**
1. Add an enum value and its `storageValue`.
2. Add its entry route and `startupEntryPath` case.
3. Add its texts in all six ARB files.
4. Set `available: true` only once its backend contract is confirmed and
   implemented (no speculative adapters).

## Capability Manager

`backendFeaturesProvider` (core), filled by `backendFeaturesOverride` (app
composition), is the single owner of the shop's `GET /meta`:
- read once per session;
- the router listens, so the read starts right after sign-in or restore;
- a fresh read on each new sign-in;
- Demo Mode uses its own fixed set and makes no request.

| `/meta` result | `BackendFeatures` | Effect |
|---|---|---|
| Envelope with features | confirmed, `apiVersion` | Features and contract resolved |
| `APP_UPGRADE_REQUIRED` (426) | `refused(appUpgradeRequired)` | Update screen |
| `MAINTENANCE` | `refused(maintenance)` | Maintenance screen |
| Network, timeout, unreadable reply | `baseline` (unconfirmed) | Degrades, never blocks, never signs out |

`compatibilityProvider` / `resolveCompatibility`:
- refusals block;
- a confirmed `api_version` with a major above 1 → update required;
- 0.x or an unreadable version → server not supported;
- an unconfirmed baseline is compatible only when no definitive refusal was
  received for the same `capabilityScopeProvider` identity.

A confirmed block is kept for that identity: a **Try again** that fails
(network, timeout, unreadable reply, so the baseline) keeps the screen
blocked. Only a confirmed compatible answer, sign-out or another
session/backend clears it. Values read while `/meta` is (re)loading are
ignored, so a previous session's answer never leaks into a new one. The
screen keeps **Sign out**; Settings stay reachable.

Session permissions (`AuthSession.permissions`) come from the token grant
and `GET /auth/session`. They are in memory only: never in the stored
session record or the read cache. `sessionPermissionsOverride` exposes them
as `SessionPermissions`; unknown (Demo Mode, a reply without permissions)
never restricts, because the server still enforces every permission.

## Feature Resolver

`core/capabilities/feature_resolver.dart`:
- **`AppFeature`** declares each feature's required backend features,
  optional backend features (workflow variants) and session permissions.
- **`resolveFeature`** (pure) and **`featureAvailabilityProvider(feature)`**
  return:
  - `available`;
  - `disabled` — a reported permission is missing, or a key an older
    backend does not report;
  - `hidden` — the shop lacks a required feature.

  Per-product rules stay with `Product.permissions`, and offline rules stay
  with the screens.
- **Workflow variants:** `StockWorkflow.of(availability)` → `countOnly` or
  `countAddRemove`.
- **Enforcement:** screens use `visible`/`usable` independently of the
  variant, and controllers check again before confirming and writing. Update
  Stock: hidden shows "not available for this shop", disabled shows the
  permission notice; both combine with the product's `stock_adjust` and
  adjustability, offline, busy and uncertain states
  (`StockUpdateController.allows`). The server still enforces every
  permission.
- **Discounts:** `AppFeature.discounts` (`product_discounts` +
  `discount_read`) and `AppFeature.discountManage` (+ `discount_manage`),
  combined with the product's own `discount_manage` and the connection in
  `discountAccessProvider` (see [product-discounts.md](product-discounts.md)).

**Adding a gated feature:**
1. Backend `_get_features()` flag.
2. An `AppFeature` entry.
3. The screen watches `featureAvailabilityProvider`.
4. A Demo Mode feature set entry.
5. Tests with and without the flag.

## Hybrid contracts

- `resolveApiContract(api_version)` → `ApiContract.mobileV1` for 1.x and for
  an unknown version.
- App composition (`product_dependencies.dart`) binds each contract to its
  data implementations, with `switch (ref.watch(apiContractProvider))`:
  today `OdooProductRepository` / `OdooProductDetailsRepository` /
  `OdooDiscountRepository` (v1) and the Demo Mode repositories.
- Mobile API **1.1.0** adds the discount endpoints to the v1 family
  (additive), so the v1 adapter serves them; there is no v2 or v4 adapter.
  "App v2" is the Flutter release, not an API contract.
- Domain repositories and pages stay single. Add a new adapter set only
  when the backend publishes a breaking contract; additive API changes need
  none.
