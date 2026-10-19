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
through `ProductDetailsRepository`, its Odoo implementation and the shared client.
Creation checks the current token's `product:name_update`, `product:price_update`
and `reference:read` scopes, barcode absence and reference data. These follow the
supplied save/reference contracts; no new speculative scope is introduced.

Immediately before saving, the repository rechecks permissions, barcode and tax
options. The original `/mupi/mobile/api/products/save` accepts barcode, name,
price and tax IDs and creates a product when no barcode matches. Its confirmed
success reply is `ok: true`, `message: "Product created successfully."` and a
product object. This original contract works without a server update or a new
capability field. A response saying a product was updated is not reported as a
successful creation. Returned product data must match the scanned barcode.

When references advertise `create_only_supported: true`, the app additionally
sends `create_only: true` and requires `action: created`. Otherwise, neither that
new parameter nor the new action field is required. Permission and validation
checks remain active for both versions.

The original save ignores `tax_ids: []`. If No Tax was selected but its response
contains default taxes or cannot confirm an empty tax assignment, the app uses
the original `/products/update` route with the confirmed ID, name and explicit
`tax_ids: []`. Success requires an empty assignment in the mapped response. A
failed follow-up is an uncertain outcome, not permission to repeat creation.

Validation/permission errors preserve entered fields. Conflicts and uncertain
outcomes block resubmission until an explicit barcode check. A discovered existing
product can be opened instead. Writes are never automatically retried. The standing
session policy still signs out on an authenticated network/timeout failure, so
drafts are not retained across that security reset. No offline writes are queued.

## Optional Odoo hardening

The additional controller changes in this workspace are optional for creation.
They advertise `create_only_supported: true` and add server-side protection against
upserting an existing barcode. Deploying them requires updating the addon code
and restarting Odoo workers; deployment is not performed by the Flutter build.

The original save route is an upsert, and find hides non-POS products. A client
precheck cannot fully prevent a race or discover every hidden matching record.
Only the enhanced server-side guard closes that gap; the compatibility path must
not be described as atomic create-only protection.

The backend implementation:

- Requires the existing price/name permissions.
- Serializes barcode saves with a PostgreSQL transaction advisory lock.
- Rejects a create-only barcode conflict across companies and archived/non-POS
  products without exposing those records or writing them.
- Validates selected taxes against active sale taxes of the POS company.
- Applies `tax_ids: []` explicitly, rather than silently inheriting default taxes.
- Rejects non-finite/negative prices and returns the confirmed `action`.

The lock coordinates this API's saves; full PostgreSQL/Odoo transaction behavior
and concurrent writes through other Odoo interfaces require deployment testing.
No new stock-write contract is introduced.

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
python -m unittest discover -s tool -p test_product_creation_contract.py
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
