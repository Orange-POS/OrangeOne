# Product creation from unknown barcodes (Task 10)

An unknown barcode opens `ProductCreationPage` in the Products feature through
the existing protected `addProduct` route (`/home/products/new?barcode=...`). The
Home feature retains scanning/lookup; it no longer owns the placeholder draft page.
The read-only barcode preserves leading zeros. Name, CHF price and explicit tax
selection are required; **No Tax** is a valid explicit selection. CHF uses the
existing integer-hundredths parser, including decimal-comma support and exact
two-decimal validation. Name is trimmed and limited to 200 characters.

The page reuses the product navbar, product-name card/stock badge, price field,
barcode row, tax sheet, notices and clear-glass action surface. Header and footer
remain fixed while the body scrolls. Unknown stock is unavailable until a backend
product exists. Success shows the confirmed product and scrolls its notice into
view; **Done** replaces creation with refreshed product details. Phone, landscape
and keyboard layouts are covered by widget tests.

## Permissions and safe writes

`CreateProduct` validates a draft in the domain layer. The Riverpod controller
owns draft and submission state, preventing duplicate submissions. All IO goes
through `ProductDetailsRepository` and the Mobile API v2 client
([integration](mobile-api-v2.md)). Creation requires the `product_create`,
`product_update_price` and `product_read` permissions (from `GET /auth/session`
for an unknown barcode), barcode absence and the `GET /taxes` options.

Immediately before saving, the repository rechecks permissions, barcode and tax
options. `POST /products` sends barcode, name (1–128 characters), `list_price`
as a decimal string and `tax_ids`; `[]` is the explicit No Tax choice (company
defaults are never applied implicitly). The endpoint never upserts:
`409 BARCODE_EXISTS` is a conflict. A `201` reply must return the scanned
barcode; it replaces the cached snapshot.

Each creation carries an `Idempotency-Key`. After an uncertain outcome the same
key is reused for the identical request, so the server replays instead of
creating twice. Validation/permission errors preserve entered fields. Conflicts
and uncertain outcomes block resubmission until an explicit barcode check; a
discovered existing product can be opened instead. No offline writes are queued.

## Backend guarantees

Barcodes are unique per company including archived products, enforced by the
server. A client precheck alone cannot prevent races; the server's create-only
semantics and idempotency keys can.

## Design and verification

Reference: Figma node `445:3079`, the user-supplied PNG/SVG, and the existing product
screens. Figma supplied section metadata and a screenshot, but the plan's MCP
limit prevented detailed component reads. Native widgets were composed from the
provided reference and repository components; exact Figma token fidelity is not
claimed. The standing brand logo, stock badge, button contrast and neutral-glass
rules take precedence over older reference details.

Commands:

```sh
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter test integration_test/app_test.dart --flavor development --dart-define=TEST_FLAVOR=development -d DEVICE_ID
```

The Python tests execute the actual controller with isolated Odoo collaborators;
they do not prove a deployed Odoo/PostgreSQL integration. Mobile integration uses
fake repositories/scanners and never creates real inventory. Live Odoo creation,
permission enforcement and device secure storage require separate manual checks.
iOS compilation remains unverified on Windows.

Executed verification (2026-10-19): all 305 Flutter tests passed, six isolated
backend-controller tests passed, and strict analysis passed. Empty, tax-selection,
ready and saved states were rendered and reviewed; final UI checks passed after
the typography refinement. The Android development APK built successfully. The
controlled integration journey passed on Samsung SM-A315F, including unknown
barcode → creation with No Tax → new details/price → Logout. No live Odoo records
were changed by these tests.
The final normal development APK was then installed, launched and confirmed
running in the foreground on the phone. The live Odoo controller was not deployed.

Original-addon compatibility correction: the capability flag is optional, and
creation is enabled for the original supplied save contract. All 308 Flutter
tests passed, including the missing-capability response, exact legacy payload and
created acknowledgment, default-tax correction, and failed correction handling.
The compatibility change was built for Android. No live product was created by
these automated tests; real server persistence remains a manual verification.
The compatibility APK was installed and launched successfully on the Samsung
phone, with its foreground activity and running process confirmed.

Returning from created product details resets lookup state and remounts the camera when the scanner route actually becomes visible. This also covers replacement navigation and system Back, allowing the same barcode to be scanned again without stale unknown-product actions.

Regression verification (2026-10-19): 310 Flutter tests passed and static analysis reported no issues. The physical Android scanner-return test passed with the real camera running before and after creation/detail navigation, controlled repositories, and injected barcode detections. No live Odoo inventory was changed; optical recognition and iOS remain unverified for this check.

## Required and optional fields (latest)

- **Required:** product name, tax and category. The tax starts as the backend's
  configured default (`default_tax_ids` of `GET /taxes`; ids that are not offered
  are ignored). Without a configured default no tax is invented and the user
  must choose (including *No Tax*). A category is chosen from `GET /categories`
  or created inline (`category_create`), and is sent as `category_id`.
- **Optional:** price (empty is `0.00`) and stock quantity. An entered quantity
  is sent as `initial_quantity`; an empty one is not sent. The form shows
  **Not Set** for it, and the created product shows *Not Set* instead of *Out
  of stock* until a count is saved (`unsetStockProvider`, session only). A
  quantity of `0` the user typed is a real zero. If the backend reports a stock
  for the new product that is not zero, that value is shown.
- **Flow.** Create Product opens the confirmation popup (name, barcode,
  category, tax, price, stock); Confirm creates, then Product Details opens
  with the success toast. There is no Done step. The screen shows no product
  name card.
