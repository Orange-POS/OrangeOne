# Task 05 — Home and product barcode lookup

## Scope and design

Home owns the authenticated scanner landing page, camera page and all barcode
lookup actions. The supplied landing PNG/SVG defines the gradient, OrangeONE
wordmark, white circle with the exported box-scan icon, “Tap to scan Barcode”,
“Scan Your Product” (the “Powered By OrangeONE” footer was removed). The barcode page follows the supplied scanner
PNG/CSS: orange header, open-corner frame, live camera status and compact last
scanned card. The exported vector icon is `assets/icons/box_scan.svg`.

Task 06 adds the separate details feature in `features/products`. Home routes
lookup results automatically through app composition; see [Product details](product-details.md).
Logout remains available through the Home wordmark Account menu.
The Figma connector was rate-limited, so visual verification used the supplied
exports. The API supplies a numeric price without a currency code; the card
shows the returned price to two decimal places without assuming CHF.


As explicitly requested, **Add product is a draft only**: the scanned barcode is
read-only; name, price and optional reference can be entered. Drafts are held in
the current page's form fields and discarded on leaving it. There is no save API,
offline write queue, product update, stock adjustment or price mutation in this
task. Product creation was added later in the Products feature
(`POST /products`, see [product creation](product-creation.md)).

## Recent scans and localization

The scanner's bottom card ("Last scanned") shows the product the user scanned
last while the scanner is idle: one card, which each new scan replaces. The Home
screen itself has no card; the card is the existing one of the barcode screen.

- A product is recorded when a lookup finds it (online or from the offline
  cache); unknown barcodes, errors and invalid codes are not. A rescan moves it
  to the top; the five latest are kept in the stored history (unchanged), but
  only the newest is displayed.
- The card shows the product name; a row of two badges with the same design as
  the stock badge (`InfoBadge`): the Category (or "No Category") first, then
  the Barcode; and below them the stock text on the left and the price as
  `CHF 12.50` on the right. Storage holds those fields, the unit, the category
  name and the product id that keeps the entry current; never the reference,
  taxes, permissions or version.
- Tapping the card runs the same lookup as a scan (`ProductLookupController.scan`
  through the existing repository and API) and opens Product Details, or the
  creation form if the product no longer exists.
- Storage is the session's encrypted read cache (`EncryptedReadCache`,
  `recentScansRepositoryOverride`), so the list survives restarts, belongs to one
  session and is deleted with it; see [offline data](offline-data.md). History
  failures never interrupt scanning.
- Home and the scanner screen (texts, tooltips, camera status and permission
  messages, stock badge labels) follow the selected language; see
  [localization](localization.md).

## API contract (Mobile API v2)

See [Mobile API v2 integration](mobile-api-v2.md).

- `GET {api_base}/products/by-barcode/{barcode}` with the session's bearer token
  (refreshed on `TOKEN_EXPIRED`). The barcode must be 1–64 printable ASCII
  characters and is path-encoded; invalid barcodes fail before any request.
- `200` returns one `Product`; `404 PRODUCT_NOT_FOUND` means no POS product has
  this barcode (the scanner offers creation). Other envelopes are protocol errors.
- The server searches the session company's POS products; the app shows the
  record it returns and does not select among duplicates locally.
- Mapped fields: positive ID, nonblank name, exact barcode, decimal-string price
  and currency, stock quantity of the POS location (null when untracked, shown
  as unavailable; negative stock is valid), unit and reference.
- `AUTH_REQUIRED`/`TOKEN_*` end the session. `PERMISSION_DENIED` or
  `COMPANY_MISMATCH` are forbidden failures that keep the session. Server
  messages are shown only when short; traces are never displayed.

## Architecture, state and cancellation

`features/home/domain` owns Product, ProductRepository and LookupProduct.
`data` owns the Odoo source, JSON mapper and repository. Presentation owns the
scanner, result panel, draft page and manual Riverpod providers. Home landing callbacks are supplied by app composition.

`app/providers/product_dependencies.dart` binds `productRepositoryProvider` at
the existing root ProviderScope. It watches the current authenticated session,
injects the authenticated Mobile API client, and cancels its Dio request when disposed.
It only logs out the same session that made a rejected request. Home widgets import another feature's presentation or data implementation.

`productLookupControllerProvider` / ProductLookupController is auto-disposed.
Idle is `AsyncData(null)`, pending is `AsyncLoading`, a completed lookup contains
its barcode and nullable product, and failure is `AsyncError(AppFailure)`.
Automatic retry is disabled. Only network/timeout read failures offer manual
retry. Repository and camera-builder providers are overrideable in tests.
Changing dependencies, signing out or leaving the scanner disposes/cancels the
request; generation and mounted checks reject late results.

Barcode validation trims outer whitespace, preserves case and leading zeros,
and rejects empty, oversized (>256 characters) or control-containing values.
Completed lookups automatically open details or the prefilled add-product draft.
Detection pauses while the destination is open and resets when it closes.
Errors offer safe read retries or Scan another barcode. Login retains single-scan
behavior. There are no automatic inventory mutations.

## Camera and navigation

The shared CodeCamera owns permission requests, denied/restricted/permanent
states, safe camera errors, Settings/retry actions, app background/resume and
controller disposal. Login retains its QR-only wrapper. Product formats common
to Android/iOS are EAN-13, EAN-8, UPC-E, Code 128, Code 39, Code 93 and ITF-14.
Android additionally enables UPC-A and Codabar. Apple Vision can report UPC-A as
EAN-13; the app deliberately does not strip its leading zero or guess a second
barcode. Codabar is not enabled on iOS because it requires newer system support.
Physical decoding across these formats still requires device verification.

Named protected routes:

| Name | Path | Input/result |
| --- | --- | --- |
| home | `/home` | Current authenticated session |
| productScanner | `/home/scan` | Back returns `false` when pushed |
| addProduct | `/home/products/new` | Validated `barcode` query parameter |

Existing startup restoration, login redirects, logout and unknown-route handling
remain. Product deep links cannot bypass authentication or restoration. The add
page validates its route input before showing a prefilled draft.

## Verification boundaries

Unit/provider/widget checks cover mapping, exact request shape, malformed or
multiple results, no match, auth versus permission failures, duplicate scans,
manual retry, disposal, stale dependencies, logout guards, draft navigation,
permission states, format filtering and enlarged text at 320×568, 390×844 and
844×390. The integration smoke journey uses fake authentication, product data and
camera callbacks; it does not call a live Odoo server or mutate inventory.

A pre-existing login-brand overflow was observed at 320 pixels with 1.6× text
while investigating scanner layouts. Login visual changes are outside this task;
scanner responsiveness is tested after authenticated startup.



