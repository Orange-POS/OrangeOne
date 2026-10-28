# Update Stock (Update, Add and Remove)

The stock pencil on the Product Details name card ("Update stock") opens the
Update Stock page (route `productStock`, `/home/products/stock`). It follows the
Update Price layout: fixed header, product name card with the stock badge,
barcode and current stock, the **Update / Add / Remove** selector, the quantity
input with a live preview, a confirmation dialog and a sticky action.

## Operations

Example with 150 units on hand (the user never calculates the result):

| Mode | Entered | Result | Request |
| --- | --- | --- | --- |
| Update (default) | 40 | 40 | `POST /products/{id}/stock-adjustments` (absolute count) |
| Add | 40 | 190 | `POST /products/{id}/stock-movements` `operation: add` |
| Remove | 40 | 110 | `POST /products/{id}/stock-movements` `operation: remove` |

- The selector (`StockOperationSelector`) keeps the entered quantity when the
  mode changes and checks it again for the new mode. It is locked while a write
  runs, after success and while the outcome is uncertain.
- The label, hint, helper text and action button follow the mode (*Counted
  Quantity* / *Quantity to add* / *Quantity to remove*; *Update Stock* /
  *Add Stock* / *Remove Stock*).
- The preview (`150 + 40 = 190 Units`, `150 \u2212 40 = 110 Units`, `New stock:
  40 Units`) appears only for a valid quantity. It is a preview: the confirmed
  quantity always comes from the backend reply, never from this calculation.
- Validation (`AdjustStock.validate`, `StockInputException`, localized by the
  screen): a non-negative number within the unit precision; Add and Remove need
  a quantity above zero; Remove cannot exceed the current stock. The action
  stays disabled until the quantity is valid.

## Rules

- Enabled only online, with the `stock_adjust` permission and stock the backend
  reports as `tracked` and `adjustable`. Untracked, lot/serial, packaged or
  owner-specific stock is never sent; the page explains that it must be
  adjusted in Odoo.
- An Update count is absolute (inventory mode), non-negative and limited to the
  decimal places of the unit rounding. Counting the current quantity again is
  allowed and audited by the backend without a stock move.
- Only the POS stock location is used (`Product.stock.location_id`); boxes,
  packages and lots are out of scope.
- Before writing, permission, adjustability and the confirmed stock are read
  again. A changed quantity requires a new review.

## Contract

Update: `POST /products/{id}/stock-adjustments` with
`{"new_quantity": "<decimal>", "location_id": <POS location>, "reason": "count"}`.
Add / Remove: `POST /products/{id}/stock-movements` with
`{"operation": "add" | "remove", "quantity": "<decimal>", "location_id": <POS location>}`
(the backend defaults the reason to *receipt* / *correction*). Both send
`If-Match` with the fresh JSON `version` (optional for movements on the backend,
always sent by the app) and an `Idempotency-Key` ([integration](mobile-api-v2.md)).
The `201` reply holds the refreshed product and the `adjustment` (Update) or
`movement` (Add/Remove). Success requires the same operation, quantity and
location, a non-negative result consistent with the reported previous
quantity, and the product reporting that stock; the shown result is the
backend's, so a quantity changed meanwhile is never overwritten by a stale
calculation. Details and the cached snapshot refresh.

| Response | Behavior |
| --- | --- |
| `412 VERSION_CONFLICT` | Reload current stock, keep the count, no retry |
| `422 BUSINESS_RULE_VIOLATION` (including removing more than is on hand), `400` | Show the server message, keep the mode and quantity |
| `403` | Permission message; the session stays |
| Transport failure / malformed reply | Uncertain: further counts blocked until "Check current stock" |
| Offline | Blocked before sending |

A failed write is never retried with a new `Idempotency-Key`: after an
uncertain outcome the identical request reuses its key, and another quantity or
mode is a new intent.

Tests: `test/features/products/stock_operations_page_test.dart` (modes, preview,
validation, confirmation, success, conflict, network, permission),
`stock_update_controller_test.dart`, `stock_update_navigation_test.dart`,
`domain/use_cases/adjust_stock_test.dart`, `domain/entities/stock_count_test.dart`
and the stock groups in `product_details_repository_test.dart`.

## Confirmation, toast and navigation (latest)

The action button (*Update Stock*, *Add Stock* or *Remove Stock*) opens the
confirmation popup; Confirm sends the request. Success
returns to Product Details with the *Stock Updated Successfully* toast and
clears the *Not Set* marker of a product created without a quantity (a count,
even zero, is a set stock). The screen uses the shared name card with Category,
Stock and Tax badges; see [product edit](product-edit.md).
