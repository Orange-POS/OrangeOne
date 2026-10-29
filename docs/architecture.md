# Architecture and implementation boundaries

## Dependency direction

Feature presentation -> domain contracts <- feature data implementations.
`app` composes dependencies through Riverpod; domain code stays independent of
Flutter, Dio, Firebase and Odoo payloads. Shared infrastructure belongs in `core`
only once a concrete cross-feature need exists. Business rules must not live in
widgets or routers. Dispose resources using Riverpod lifecycle hooks.

The initialization diagnostic remains presentation-only, at
`/diagnostics/initialization`. The authentication feature implements pages/widgets/
providers, pure-Dart session/challenge entities and repository/use-case contracts,
and data-layer QR/response mapping, remote IO and repository implementation.
Shared Dio, the Mobile API v2 client, secure storage and failures live in core; branding lives in
shared/theme. The app starts at `/login`, nests its QR scanner, and guards `/home`
through the verified session state. Redirect policy is separate from route creation.
Unknown routes show a safe fallback. Bootstrap validates that
the native flavor matches the Dart environment before creating the ProviderScope;
missing or mismatched flavors fail immediately instead of mounting the wrong app.

## Risks and edge cases

- Pair each flavor with its matching entry point; CI builds every pair.
- Bundle IDs are provisional and require product-owner confirmation before stores.
- Odoo permissions and stock adjustments must be enforced server-side. Agree API
  version, authorization, session expiry and error contracts before implementation.
- Future writes need idempotency and retry/conflict policy before offline sync.
- QR camera permission/lifecycle handling is implemented in authentication.
  Product-barcode scanning remains a separate future task.
- Firebase registration and consent behavior are external dependencies; startup
  currently works without service credentials.
- Android debug and unsigned iOS release compilation do not prove signed release
  readiness. Execute device smoke tests and signed release validation before launch.

## Testing strategy

Use unit tests for domain rules, repository contract tests with mocktail where
appropriate, provider tests for state transitions and widget tests for user-visible
behavior. Integration tests cover real platform startup and later critical flows.
Do not mock production behavior into the application just to satisfy a test.

## Design

Use the supplied Figma file as the source of approved UI. Extract reusable theme
and components when approved designs are implemented. The initialization screen
is a diagnostic placeholder and makes no claim to implement the design system.

The two authentication screens use the inspected Figma nodes and supplied exports.
Home is a minimal signed-in destination rather than a complete inventory dashboard.
See [authentication](authentication.md) for the source contract, trusted-origin
policy, secure-storage ownership, permission setup and navigation details.

## Home scanner and product-details boundary

Home owns its scanner landing page, barcode camera page, all product-lookup
actions, Riverpod state, lookup domain contracts and Odoo lookup data layer.
The products feature owns product details, permissions, confirmed name/price
updates and refresh. It contains no scanner implementation. Cross-feature session
composition remains in app/providers/product_dependencies.dart.


