# Update Stock (absolute stock count)

The stock pencil on the Product Details name card ("Update stock") opens the
Update Stock page (route `productStock`, `/home/products/stock`). It follows the
Update Price layout: fixed header, product name card with the stock badge,
barcode and current stock, the counted quantity input, a confirmation dialog
with current, counted and difference values, and a sticky action.

## Rules

- Enabled only online, with the `stock_adjust` permission and stock the backend
  reports as `tracked` and `adjustable`. Untracked, lot/serial, packaged or
  owner-specific stock is never sent; the page explains that it must be
  adjusted in Odoo.
- The count is absolute (inventory mode), non-negative and limited to the
  decimal places of the unit rounding. Counting the current quantity again is
  allowed and audited by the backend without a stock move.
- Only the POS stock location is used (`Product.stock.location_id`); boxes,
  packages and lots are out of scope.
- Before writing, permission, adjustability and the confirmed stock are read
  again. A changed quantity requires a new review.

## Contract

`POST /products/{id}/stock-adjustments` with
`{"new_quantity": "<decimal>", "location_id": <POS location>, "reason": "count"}`,
`If-Match` with the fresh JSON `version` and an `Idempotency-Key`
([integration](mobile-api-v2.md)). The `201` reply holds the refreshed product
and the adjustment; success requires the same quantity and location and the
product reporting the counted stock. Details and the cached snapshot refresh.

| Response | Behavior |
| --- | --- |
| `412 VERSION_CONFLICT` | Reload current stock, keep the count, no retry |
| `422 BUSINESS_RULE_VIOLATION`, `400` | Show the server message, keep the count |
| `403` | Permission message; the session stays |
| Transport failure / malformed reply | Uncertain: further counts blocked until "Check current stock" |
| Offline | Blocked before sending |

Tests: `test/features/products/stock_update_controller_test.dart`,
`test/features/products/stock_update_navigation_test.dart`, the stock group in
`test/features/products/product_details_repository_test.dart`.
