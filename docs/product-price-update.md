# Task 07 — Dedicated product price update

## Workflow and ownership

The existing Products feature owns this workflow. Product details' Update Price
action pushes named route `productPrice` (`/home/products/price?barcode=…`). The
page loads the current product and server permissions through the injected
`ProductDetailsRepository`. Initial loading, unavailable product, read failure,
permission denial, empty/invalid/unchanged input, saving, uncertain outcome and
acknowledged success are explicit states.

The fixed navbar and the shared `ProductActionSurface` keep navigation and a
56-point primary action visible while the middle scrolls. The action surface
reuses the user's neutral clear glass, blur and 12-point top corners. Keyboard
insets move it above the keyboard. Product/context/form/status/dialog widgets are
separate from the page and never call APIs. The reference is Figma collection
220:1689 and the supplied SVG/PNG; Figma MCP returned its plan limit, so visual
verification used the exports. Description/category are not invented when the
backend omits them. Existing exported tag/barcode assets are reused.

The page presents the old and proposed prices in a confirmation dialog before
any write. Cancellation preserves the draft. During a save, input, repeated
submission and user back navigation are blocked. Success uses Odoo's validated
returned product, normalizes the field and displays Done. The details controller
is invalidated to reload authoritative data; Done returns to the existing details
page in the normal pushed journey. Authentication redirects guard the new route,
including session restoration, expiration, logout and direct navigation.

## CHF validation and confirmed pricing contract

CHF is explicitly fixed in the field's non-editable prefix and display labels,
as requested. `ChfPrice` parses integer hundredths before transport conversion:

- Zero and positive amounts, with at most two decimal places, are accepted.
- Dot or comma is a decimal separator; thousands separators, currency text,
  negative signs, exponent notation, NaN/infinity and extra precision are rejected.
- Whole numbers and one-place fractions normalize to two decimals. Leading zeros
  are accepted. No silent rounding is performed on entered amounts.
- Unchanged displayed amounts cannot submit. Integer hundredths must fit the
  cross-platform exact integer range and survive a two-decimal double round trip;
  amounts outside accurate transport representation are rejected. This is a
  technical precision guard, not an invented business maximum.
- CHF accounting precision is 0.01; cash-only 0.05 rounding is not introduced.

Contract (Mobile API v2, [integration](mobile-api-v2.md)):

1. Read the product by barcode (or conditionally by id) on the session
   `api_base`; `product_update_price` in `Product.permissions` enables editing.
2. After confirmation, re-read permissions, product identity and price. A
   changed price requires a new review/confirmation; a missing product or
   revoked permission prevents the write.
3. `PUT /products/{id}/price` with `{"list_price": "<decimal string>"}`,
   `If-Match: "<version>"` from that fresh read and an `Idempotency-Key`.
4. Require an acknowledged product with the requested id, barcode and price.
   Protocol failures cannot report success.

The endpoint updates the product's sales price; it does not evaluate pricelist
rules or a business upper limit, and the client does not fabricate them.
A concurrent change between the preflight and the write is rejected with
`412 VERSION_CONFLICT`: the screen reloads the current price, keeps the draft and
never retries automatically.

## Failure and lifecycle behavior

The Mobile API client separates transport, protocol and API error codes. Existing typed
application failures sanitize messages and distinguish authorization from invalid
sessions. Invalid sessions clear only the matching secure session. No new storage,
preferences, global authorization headers, secrets or network logging is added.

Requests and retries remain explicit; no write is automatically repeated. A lost
connection or malformed acknowledgment after dispatch may mean a committed write.
The workflow then disables further saves and offers **Check current price**, a
read-only recovery action. Pull-to-refresh also performs only reads and preserves
the entered draft. Refreshing reconciles current values before a new confirmation;
it does not claim that an unacknowledged write succeeded. Ordinary failures and
permission denials preserve the draft. Generation/mounted guards and repository
cancellation prevent obsolete results from replacing a newer session or disposed
page state.

## Verification

`flutter analyze --fatal-infos --fatal-warnings` passed; the full
`flutter test --coverage` suite passed **241 tests**. Added tests cover CHF
parsing/precision, confirmation cancellation, unchanged/invalid drafts, single
submission, permission revocation, changed current prices, safe read recovery,
late completion after disposal, acknowledgment mapping, protected navigation,
Done returning refreshed details and error/empty/success widgets. Fixed controls
and keyboard behavior were checked at 320×568, 390×844 and 844×390 with enlarged
text. Empty/invalid/ready/confirmation/saving/success renders were inspected using
the app fonts. The controlled Android integration test passed on SM A315F on
16 October 2026: QR login, scan, details, dedicated price input, confirmation,
success, Done returning refreshed details, unknown-barcode draft and logout.
iOS builds and real Odoo price writes were not exercised by these tests.
The normal arm64 development APK built successfully and was installed/launched
on the phone after the integration run; live Flutter preview is restored.


## Confirming update responses (Issue #12)

A matching product ID/barcode is insufficient to report success. The price
controller also compares the returned CHF amount with the confirmed amount at
hundredth precision. A mismatch enters the existing uncertain state, preserves
the draft and requires an authoritative refresh before another write. It never
retries automatically or replaces the draft with an unconfirmed response.
