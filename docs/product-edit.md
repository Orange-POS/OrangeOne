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

## Confirmed contract

- `products/find` supplies the current name and tax labels/identities.
- `auth/token/check` provides `product:name_update` for both editable fields.
- `products/references` requires `reference:read`, returning active sale taxes
  for the POS company. Default tax IDs apply to creation, not an existing edit.
- `products/update` accepts `product_id`, trimmed `name`, and optional `tax_ids`.
  Omitting tax_ids preserves existing taxes; an empty array explicitly clears
  them. The response must contain a valid matching product before showing success.

Tax IDs and backend payloads stay in the domain/data boundary. Widgets use the
controller and never call the API. No name/price/stock fields beyond name and tax
are submitted. Names must contain 1–200 characters and no control characters.

## Safety and edge cases

Name-only edits preserve every current tax, including multiple assignments and
missing tax identities. Tax selection is disabled when references cannot be read;
name editing remains available with its own permission. Selecting one tax or No
Tax explicitly replaces all existing assignments, as the supplied single-choice
workflow specifies. Dismissing the sheet leaves the draft unchanged.

Before saving, the controller rechecks product identity, permission and current
name/tax information, and revalidates selected IDs against fresh company tax
references. A changed server snapshot requires review. This is not an atomic
version check: the supplied endpoint has no expected-version contract, so a
concurrent write between preflight and save remains a backend limitation.

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
