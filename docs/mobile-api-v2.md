# OrangeONE Mobile API v2 integration

The app talks only to the OrangeONE Mobile API v2 served by the Odoo addons
`mupi_mobile_auth` and `mupi_mobile_pos_api` (Orange-POS/odoo_addons PR #192,
addon version 19.0.2.0.0). The contract is
`custom_addons/mupi_mobile_auth/doc/openapi.yaml` in that repository; it is the
source of truth for paths, fields and error codes. The legacy JSON-RPC routes
(`/mupi/mobile/...`) and their client were removed in stage 8.

## Transport (`lib/core/network`)

| Piece | Responsibility |
| --- | --- |
| `dio_provider.dart` | Shared Dio: flavor timeouts, JSON, no redirects, no body/header logging |
| `mobile_api_client.dart` | REST calls below the session `api_base`; parses `{data, meta}` / `{error, meta}`; maps `error.code` to `FailureKind`; sends `X-Request-Id`, `Authorization`, `Idempotency-Key`, `If-Match`, `If-None-Match` |
| `authenticated_mobile_api.dart` | Binds the client to the signed-in session; reads the access token per request and refreshes once on `TOKEN_EXPIRED` |
| `idempotency_keys.dart` | UUID v4 per write; an uncertain outcome keeps the key for the identical retry |
| `product_payload.dart` | Validates `Product` / `ProductSummary` payloads (decimal strings, ISO currency) |

Base URL: the POS QR `api_base` (`{origin}/api/orangeone/mobile/v1`), checked
against the flavor's trusted origin. Error codes map as follows:
`VALIDATION_FAILED`, `BUSINESS_RULE_VIOLATION`, `QR_INVALID` → validation;
`AUTH_REQUIRED`, `TOKEN_*` → unauthenticated; `PERMISSION_DENIED`,
`COMPANY_MISMATCH`, `DEVICE_MISMATCH` → forbidden; `NOT_FOUND`,
`PRODUCT_NOT_FOUND` → notFound; `BARCODE_EXISTS`, `VERSION_CONFLICT`,
`IDEMPOTENCY_KEY_REUSED`, `SYNC_TOKEN_EXPIRED` → conflict; `RATE_LIMITED`;
`APP_UPGRADE_REQUIRED`; `MAINTENANCE` / `SERVICE_UNAVAILABLE` → network (offline
fallback). Server messages up to 500 characters are shown; traces never are.

## Endpoints used

| Feature | Endpoint | Notes |
| --- | --- | --- |
| QR login | `POST /auth/qr-exchange` | QR `v: 2`, `type`, `challenge_id`, `nonce`, `pos_config_id`, `api_base`, `expires_at`; device install id |
| Token refresh | `POST /auth/token/refresh` | Rotating refresh token, single flight, 30 s margin |
| Restore / permissions | `GET /auth/session` | Startup validation (15 s); permissions for not-found barcodes |
| Logout | `POST /auth/logout` | Revokes the token family; local state is cleared first |
| Scan | `GET /products/by-barcode/{barcode}` | Barcode path-encoded; `PRODUCT_NOT_FOUND` → creation flow |
| Details refresh | `GET /products/{id}` | `If-None-Match` with the last ETag; 304 keeps details and permissions |
| Search | `GET /products` | `q`, `category_id`, `cursor`, `limit` (domain: `SearchProducts`) |
| Create | `POST /products` | `tax_ids: []` is the explicit No Tax; never upserts |
| Edit | `PATCH /products/{id}` | Only changed `name`, `tax_ids`, `category_id` (null removes) |
| Price | `PUT /products/{id}/price` | `list_price` decimal string |
| Stock count | `POST /products/{id}/stock-adjustments` | Absolute `new_quantity`, POS `location_id`, `reason: count` |
| Tax / category pickers | `GET /taxes`, `GET /categories` | Categories: first page of 100; `default_tax_ids` seeds a new product's tax |
| Create category | `POST /categories` | `{name}` with `Idempotency-Key`; needs `category_create`; the created category is selected in the form |
| Offline sync | `GET /products/changes` | `since`, `limit`; see [offline data](offline-data.md) |

Not used yet: `GET /meta` (minimum app version, feature flags),
`GET /products/{id}/history`, `POST /telemetry/events`.
`POST /auth/qr-challenges` is called by the Odoo POS UI, not the app.

## Concurrency and duplicate protection

- **Version vs ETag.** Updates send `If-Match: "<version>"` with the JSON
  `version` of a product re-read just before the write, never the ETag. The ETag
  is used only for `If-None-Match`. Offline/cached details have no version and
  cannot be written.
- **412 `VERSION_CONFLICT`.** Nothing is retried or overwritten. Edit, price and
  stock screens reload the latest server data, keep the user's draft and show
  "This product was changed on another device".
- **Idempotency.** Every create/update/stock write carries `Idempotency-Key`.
  A transport failure, timeout or unreadable reply keeps the key, so repeating
  the identical request (same body and version) is applied once or replayed by
  the server. Any server answer settles the key. Screens additionally block
  duplicate taps and require a "Check" read after an uncertain outcome.
- **Acknowledgements.** A write succeeds only if the returned product matches
  (barcode; stock count and location for adjustments). The acknowledged product
  replaces the cached snapshot.

## Permissions

`Product.permissions` (or `GET /auth/session` for unknown barcodes) maps to
`ProductAccess`: name edit, price, taxes, category, create, stock, history and
reference reads. The backend re-checks every write; the app checks again before
writing and never caches permissions. Stock counting additionally requires
`stock.adjustable` (not lot/serial, packaged, owner-specific or untracked stock).

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

Real-backend checks against a local Docker Odoo are documented in
[testing](testing.md#real-backend-validation).
