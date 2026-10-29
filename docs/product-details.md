# Task 06 — Product details

Task 07 replaces the original price dialog with the dedicated
[product price update workflow](product-price-update.md). Task 08 replaces the
name dialog with the dedicated [Name & Tax page](product-edit.md). Both workflows
retain server permission checks and refresh details.

## Ownership and navigation

Home retains scanner and initial exact barcode lookup. App composition routes a
completed match automatically to `/home/products/details?barcode=…`; a null match
opens `/home/products/new?barcode=…` automatically. There is no intermediate user
confirmation. The scanner stops while a destination is open and resets on return.
Details is a separate `features/products` data/domain/presentation feature. It
loads authoritative data itself, supports direct navigation, refresh and safe
loading/empty/failure states. All routes remain protected by session restoration
and logout checks. Add product remains a prefilled draft without saving.

## Header, actions and localization

- The top bar has no back arrow; the title stays centered. A round **Open
  Scanner** button (floating, bottom right) returns to the scanner with the
  previous navigation (`pop`, or `goNamed('productScanner')`). System back still
  works. The "Powered by OrangeONE" footer was removed.
- The name card shows a Category badge to the left of the Stock badge with the
  same design (`InfoBadge`); a product without a category shows "No Category".
  Long category names are truncated; the badges wrap on narrow screens.
- Every text of the screen (title, labels, tooltips, states, tax text, sync
  indicator) follows the selected language of the six supported; see
  [localization](localization.md).

## Server operations (Mobile API v2)

The authenticated Mobile API v2 client, timeouts and secure session are reused
([integration](mobile-api-v2.md)). The details repository is bound to the
session `api_base`, a per-request access token and a disposal cancellation token.
No authentication data is logged.

- `GET /products/by-barcode/{barcode}` on first load, then
  `GET /products/{id}` with `If-None-Match`: `304` keeps the previous details
  and permissions; a removed or re-barcoded product falls back to the barcode
  lookup. The JSON `version` and the ETag are kept separately.
- Mapped data: name, description, barcode, reference, decimal price and
  currency, taxes (percent taxes show their percent; other types keep their
  names), category, POS-location stock and unit, and `Product.permissions`.
- Name/tax/category edits use `PATCH /products/{id}`, price `PUT
  /products/{id}/price` and stock counts `POST /products/{id}/stock-adjustments`,
  each with `If-Match` (JSON version) and an `Idempotency-Key`.

The server enforces permissions again on every write and rejects stale versions
with `412 VERSION_CONFLICT`, which reloads the details without retrying.
The form validates trimmed names (1–128 characters) and finite nonnegative prices.
The explicit Confirm update action performs one write, prevents duplicate
submission, then re-reads details and permissions. Writes are never automatically
retried. After an uncertain network outcome, refresh before submitting again.
Authentication rejection clears only the matching current session; permission
denial does not sign out. UI errors exclude backend internals.

## Design and unsupported fields

Reference: Figma node 182:724 and the user-supplied PNG/SVG. The Figma connector
returned its plan limit, so implementation/visual inspection used supplied exports.
The page follows the orange hero, product card, stock pill, rounded white body,
barcode/price/tax rows and discount card with management actions. Layout scrolls
and adapts to phone widths and text scaling.

The server does not return currency, description or category: these are not
fabricated. The user confirmed CHF as the display currency; prices show CHF and two decimals.
Stock update is visibly disabled with an explanation: no stock-write endpoint or
scope is supplied. It cannot mutate inventory.

Discount is explicitly **Mock data / Preview only** in every flavor. Its local
editor updates offer name and a validated 0–100 percentage, never the product's
price or backend. The screenshot's 200% example is replaced by 20%. The sample
schedule remains 12–18 Oct 2026; no real promotion is inferred. Local edits are
discarded when the details page is removed. A later backend contract is required
for discount persistence, actual scheduling and stock adjustments.

## Verification

Focused tests cover mapping and malformed responses, missing products, permissions,
origin and write payloads, session rejection versus authorization failure,
input validation, controller refresh, loading/empty/error widgets, confirmation,
automatic scanner navigation and returning to scan. Camera/network dependencies
are controlled; no real Odoo records are mutated by tests.

Verification on 16 October 2026: `flutter analyze --fatal-infos
--fatal-warnings` passed with no issues; `flutter test --coverage` passed all
197 tests. The controlled Android integration test passed on SM A315F via
wireless debugging (login, automatic details/draft routing, back and logout).
The product page was rendered at 390×844 and visually inspected against the
supplied export. Enlarged-text widget layouts passed at 320×568, 390×844 and
844×390. iOS builds and real Odoo name/price writes were not exercised.
The final arm64 development APK built successfully and the normal app was
installed/launched on SM A315F; live Flutter preview was restored after testing.

UI refinements: header navigation is fixed above the scrollable body. A separate
safe-area-aware glossy action bar fixes the 56-point Update Price / Update Stock
controls at the bottom, reserving space so content is never obscured. Wide layouts
place buttons side by side. CHF is displayed as requested; pull-to-refresh replaces
the redundant refresh buttons. Hero and discount card shadows follow the supplied
SVG. These fixed-header/sticky-action conventions are recorded in AGENTS.md.

## Success toast

After Edit Name & Tax, Price, Stock or Creation succeeds, this screen shows the
success toast above the Open Scanner button (`ProductSuccessToast`, the shared
success notice design, about five seconds). The hero is the shared glass card
with the Tax row (see [product edit](product-edit.md)).

The Tax appears only in the hero (not as a separate row below Price). The glass shadow is drawn outside the card only, so the theme colors are not darkened.
