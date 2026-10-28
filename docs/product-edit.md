# Product Name & Tax editing

Task 08 adds `/home/products/edit?barcode=…` (`productEdit`) inside Products.
The product-details header pencil opens this page. Home continues to own barcode
scanning and lookup. The page uses the existing session guard, shared API client,
repository injection and typed failures.

The fixed header and neutral clear-glass action footer remain visible while the
middle content scrolls. The shared product-name card includes the live stock
badge. Save Changes is disabled until a valid change exists, displays Updating
during submission, and becomes Done only after a valid backend acknowledgement.
The tax selection sheet uses company sale taxes and offers explicit No Tax.

## Contract (Mobile API v2)

- Details come from the product read (`GET /products/by-barcode/{barcode}` or
  `GET /products/{id}`), including `version`, taxes, category and permissions.
- `product_update_name` enables the name, `product_update_taxes` the tax picker
  and `product_update_category` the category picker.
- `GET /taxes` lists the session company's sale taxes; `GET /categories` lists
  categories (first page of 100).
- `PATCH /products/{id}` sends only changed fields (`name`, `tax_ids`,
  `category_id`) with `If-Match` and an `Idempotency-Key`. `tax_ids: []`
  removes all taxes; `category_id: null` removes the category. The response must
  return the matching product before success is shown.

Tax and category IDs stay in the domain/data boundary. Widgets use the
controller and never call the API. Names must contain 1–128 characters and no
control characters.

## Safety and edge cases

Name-only edits preserve every current tax, including multiple assignments and
missing tax identities. Tax selection is disabled when references cannot be read;
name editing remains available with its own permission. Selecting one tax or No
Tax explicitly replaces all existing assignments, as the supplied single-choice
workflow specifies. Dismissing the sheet leaves the draft unchanged.

Before saving, the controller rechecks product identity, permission and current
name/tax information, and revalidates selected IDs against fresh company tax
references. A changed server snapshot requires review. The write carries the
freshly read `version`; a concurrent change after the preflight returns `412`,
which reloads current data and keeps the draft.

Concurrent saves and edits while saving are blocked. Recoverable failures keep
the draft. An unconfirmed write locks further writes until a safe read checks the
current product; there is no automatic write retry or offline write queue.
Success invalidates the details provider so returning with Done shows new data.
Session expiration continues to clear secure session state and redirect to login.

## Verification

Tests cover domain validation, tax mapping, exact update payloads, malformed
acknowledgements, permissions, unavailable references, duplicate saves, disposal,
uncertain-write recovery, navigation, success and responsive widget states.
Tests use controlled repositories/transport and never modify real Odoo records.
On 16 October 2026, strict analysis and formatting passed, and all 265 unit/widget
tests passed. The controlled Android journey passed on SM A315F: login, automatic
scan routing, price update, pencil navigation, name save, Done with refreshed
details, draft routing and logout. Rendered prefilled, invalid, ready, tax-sheet,
saving and success states were inspected at 390×844; enlarged-text layout tests
passed at 320×568, 390×844 and 844×390.
The normal arm64 development APK also built successfully and was installed and
launched on SM A315F; the live Flutter preview was restored after testing.
The attached PNG/SVG are the visual reference: Figma MCP access was blocked by
the Starter plan limit. iOS builds require macOS; real backend writes require
separate acceptance testing against the deployed module.


## Review corrections (Issues #12, #13 and #14)

Save success requires matching identity, normalized submitted name and, when
explicitly selected, the exact returned tax assignment as a set. Missing tax IDs
cannot confirm an explicit assignment. Mismatch preserves the draft in the
uncertain state and requires a read before another submission; name-only edits
continue omitting tax changes.

Conflict and permission refreshes retain explicit tax IDs, including No Tax
(`[]`). Fresh references revalidate this intent. Removed options remain visible
as unavailable and block saving until the user chooses a permitted option;
reference/permission loss never silently converts the draft into preserve-existing
semantics. The form distinguishes reference availability from selection validity
so a removed selection can still be corrected when references are available.

Details and edit screens share the same current-tax label: omitted/null/false
tax data is unavailable, an explicitly empty list is confirmed unassigned, and
populated taxes display their names. This display distinction does not invent
backend assignments or permissions. Regression tests cover all five mapper and
widget cases and mutation/conflict/permission/reference outcomes.

## Shared editing experience (Edit Name & Tax, Price, Stock, Creation)

All four screens follow one flow and one set of components:

- **Header.** The pencil action in the navigation bar is replaced by the cloud
  sync icon (`ProductSyncNavButton`, as on Product Details). The cloud is no
  longer part of the product name card.
- **Name card (glass hero).** Product Details, Edit, Price and Stock share one
  hero card (`ProductNameCard(detailsLayout: true, taxText: …)`): a glass pane
  (blur, 10% tint, thin white edge, soft shadow; the scaffold's colors show
  through) with the Category pill, name (pencil on Details only), reference,
  Stock pill (pencil on Details only), a **Tax row** and the **Barcode** row.
  Edit, Price and Stock pass `showActions: false`. The separate
  Tax card of Edit Name & Tax was removed. Creation has no card (the product
  does not exist yet). Tax percentages are shown once (`15%`, not `15% (15%)`;
  `ProductReferenceModel.taxLabel`).
- **Save flow.** *Save Changes* opens the confirmation popup
  (`ProductConfirmDialog`, `PriceChangeDialog`, `StockCountDialog` share one
  design). Nothing is sent before **Confirm**. On success the form returns to
  Product Details (`pop`, or `pushReplacement` after creation) and the success
  toast (`ProductSuccessToast`, the existing success notice design, fed by
  `productSuccessProvider`) appears above the Open Scanner button for a few
  seconds. On failure the form stays with its entries and shows the error.
  Duplicate submissions stay blocked and the busy button stays orange.
- **Categories.** The category picker offers every category and, with the
  `category_create` permission, an add row (`POST /categories`, idempotent).
  A created category is added to the list and selected for the current form.
- **Language.** All texts are localized in the six languages. Server-provided
  and some controller messages (for example uncertain-outcome hints) stay
  English. The app never names the backend product in its texts; a test
  (`test/app/no_vendor_names_test.dart`) guards this and that "Powered By" is
  shown on the Login Home screen only.
