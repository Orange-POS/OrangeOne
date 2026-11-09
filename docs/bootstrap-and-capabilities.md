# Configurable bootstrap, capabilities and hybrid architecture

One app version serves shops with different addon versions, contracts,
permissions and workflows. Background and decisions:
[configurable-bootstrap-analysis.md](configurable-bootstrap-analysis.md).

## Startup sequence

```
bootstrap(AppEnvironment)                       lib/bootstrap.dart
  flavor + ApplicationSettings check            → ConfigurationErrorApp on error
  logger, Crashlytics reporter, error hooks
  loadStartupConfiguration (saved workflow, ≤ 2 s, never fails)
  runApp(ProviderScope(… savedStartupConfigurationProvider …))
router (initial '/startup' splash)
  SessionController restore (unchanged: 15 s deadline, strict validation)
  Capability Manager: GET /meta right after sign-in or restore
  bootstrapRedirect → compatibility screen | home | the workflow's entry
```

## Configurable bootstrap

- **Workflows** (`features/startup/domain/entities/startup_workflow.dart`):
  `StartupWorkflow.qrLogin` (available) and `credentialsLogin` (registered
  but **not available**: the Mobile API has no credentials endpoint, and the
  app never invents one).
- **Saved configuration:** `StartupConfiguration`, stored as a nonsecret
  value through the injectable `SecretStore` (key
  `orangeone.startup_workflow`, like the language preference). It is read
  once in `bootstrap()` before the first frame (2-second limit), so routing
  never waits for storage. Unknown, unavailable or unreadable values fall
  back to QR login.
- **Selection:** Settings → *SIGN-IN* (`StartupWorkflowSection`, composed by
  the router into `SettingsPage.startupSection`).
  `StartupConfigurationController.select` saves available workflows only;
  if saving fails, the choice stays for the current run.
- **Bootstrap Resolver** (`app/bootstrap/bootstrap_resolver.dart`), a pure
  function used as the GoRouter redirect:
  1. **Compatibility.** A real signed-in session whose shop refused the app
     sees only `/compatibility`. Demo Mode is never blocked. Settings stay
     reachable.
  2. **Authentication.** `authenticationRedirect` decides, unchanged.
  3. **Starting component.** The login entry is
     `startupEntryPath(configuration.effectiveWorkflow)`.

**Adding a workflow:**
1. Add an enum value and its `storageValue`.
2. Add its entry route and `startupEntryPath` case.
3. Add its texts in all six ARB files.
4. Set `available: true` only once its backend contract is confirmed.

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
- an unconfirmed baseline is always compatible.

The compatibility screen offers **Try again** (reads `/meta` again) and
**Sign out**.

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
  `countAddRemove`. The Update Stock screen uses it; the behaviour is the
  same as before.

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
  today `OdooProductRepository` / `OdooProductDetailsRepository` (v1) and
  the Demo Mode repositories.
- Domain repositories and pages stay single. Add a new adapter set only
  when the backend publishes a breaking contract; additive API changes need
  none.
