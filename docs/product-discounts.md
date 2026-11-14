# Product discounts

Product discounts (the Product Discounts section of Product Details,
Discount Details, Create/Edit, Pause/Resume, Archive) over the OrangeONE Mobile API **1.1.0** discount
endpoints of `mupi_mobile_pos_api` 19.0.2.2.0 with `mupi_product_discount`
19.0.1.0.0. Source of truth: `custom_addons/mupi_mobile_auth/doc/openapi.yaml`
and `custom_addons/mupi_product_discount/doc/api-schema.md` (revision 4) in
the addons repository.

## Availability

| Shop / user | Result |
|---|---|
| `GET /meta` without `product_discounts` (older addons, or updated addons without the discount addon) | No discount UI and no discount request; everything else unchanged |
| `product_discounts` listed, `discount_read` not granted | No discount UI |
| `discount_read` only | Read-only list on Product Details and details |
| `discount_read` + `discount_manage` (session) and `discount_manage` of the product | Create, edit, pause, resume, archive |
| Offline | Reads fail with the offline notice; all writes disabled, nothing queued or replayed |
| Demo Mode | Hidden (Demo Mode has no discount data) |

Decided by the Feature Resolver (`AppFeature.discounts`,
`AppFeature.discountManage`), the product's `Permissions.discount_manage`
(false for products the POS never discounts) and the read cache's offline
state, combined in `discountAccessProvider`. Controllers check again before
every confirmation and write; the server enforces everything again. Discounts
are never enabled because of the app or API version alone.

## Code

```
lib/features/discounts/
  domain/entities/discount.dart          Discount, schedule, repeat, money, status
  domain/entities/discount_draft.dart    form state, client validation, live preview
  domain/repositories/discount_repository.dart
  data/models/discount_model.dart        strict contract mapping, DiscountInput body
  data/data_sources/discount_remote_data_source.dart
  data/repositories/odoo_discount_repository.dart
  presentation/providers/                list, details actions, form controller (save, archive, pause/resume)
  presentation/pages/                    details, form
  presentation/widgets/                  Product Discounts section (Product Details), form sections, navigation helpers
```

App composition (`product_dependencies.dart`) binds `discountRepositoryProvider`
to the v1 adapter (`ApiContract.mobileV1`: 1.1.0 is additive). The router
passes the product id and the product's `discount_manage` to the discount
pages (`DiscountScope`) and composes the Product Discounts section into Product Details
(`ProductDetailsPage.discountsBuilder`), so neither feature imports the
other's presentation. `ProductScaffold`, `ProductNavbar` and
`ProductActionSurface` moved to `shared/widgets` for that reason.

## Screens

| Route | Screen |
|---|---|
| `productDetails` | "Product Discounts" section under the price (`ProductDiscountsSection`): the count and every discount card (value, type, schedule, status pill, edit pencil; no switches), then the compact "Create New Discounts" card (`DiscountCreateCard`, only with manage access; "Confirm earlier discount" at the limit with an unresolved create). A card or its pencil opens the edit form when the discount can be changed, otherwise the read-only `productDiscountDetail`. Forms return straight here with their result; the list is read again after every confirmed write. There is no separate overview or list screen |
| `productDiscountDetail` | One discount: value, server preview, schedule, timezone, repeat, minimum, status, applies now; Edit, Pause/Resume, Archive. Reached from a card without write access (read-only); without `discount_id` the route shows Product Details |
| `productDiscountForm` | Create (no `discount_id`) or Edit: live preview, Fixed Price / Percentage / Collective, Date & Time with No End Date, order Price card, Discount Preview, Discount Type (Lucide banknote / percent / package icons, the selected type's icon in front of its input), Date & Time and Minimum Quantity cards that open and close smoothly, Repeat Schedule; the start/end date opens a calendar card and the time a 24-hour wheel card (hour 00-23, minute 00-59), and Repeat Schedule a card with the options, all sliding up from the bottom (`discount_pickers.dart`); archive icon in the navigation bar in edit mode (`DELETE /discounts/{id}`); the shared Price card (`InfoRowCard.price`) shows the regular price as read-only reference information on create and edit (no pencil, also with `update_price`), as Discount Details does. Saving a discount never writes the product price; it stays editable only through the price workflow on Product Details (`productPrice`) |

## Write rules

- Every write is confirmed in a dialog first and sent once; duplicate taps
  are blocked while busy. On the edit form, Save and Archive share one busy
  state (`DiscountFormController`): while either is pending the other, the
  inputs and leaving the form are blocked; a failure keeps the draft.
- `Idempotency-Key` for every write (`IdempotencyKeys`): new per intent,
  reused only for the identical request after an uncertain outcome. A 401
  or 429 keeps the key too: the server checks those before it reserves the
  key, so they say nothing about an earlier attempt.
- A create without a confirmed answer stays pending, exactly as sent. A
  list read cannot settle it (an equal record may be another operator's;
  an empty list may race a request still running), so every next save
  first replays it unchanged with its original key. The server waits for a
  running original, returns what it committed, or runs it now; only then
  is the outcome known:
  - same values (also `20` and `20.00`): the replay is the save;
  - changed values: Save first asks to confirm the original offer, not the
    edited one ("Confirm the earlier offer first", `DiscountReplayDialog`:
    the retry sends that request and may create it now). It lists every
    term of the original (value, start and end, repeat, minimum quantity)
    and marks each term the edit changed with the edited value, so a
    schedule-only edit is not hidden behind an equal amount; Cancel sends
    nothing and keeps the edit. A created original is then edited with the changes
    (`createdMeanwhile`); a refused one sends nothing else
    (`originalRefused`). Either way the edited terms need their own Save
    and ordinary confirmation;
  - no answer again: the original stays pending, never replaced by an
    unsent draft.
- The pending create lives in the session's `PendingWrites` (body exactly
  as serialised, original key, send time; one per product), not in the
  form: closing the form, disposing its controller or rebuilding the
  repository keeps it, and reopening Create Discount for the product shows
  its values and the guard again (`pendingCreate`). The repository refuses
  any other create for that product until it is settled
  (`DiscountRefusal.pendingCreate`), so no path can send a second one.
  App composition makes one store per session identity (environment,
  server, company, user, token family) — the server's idempotency scope
  is the token family — so another shop, user or session never sees it.
  It is memory only (writes are never persisted or queued).
- At the product's discount limit (a lost create may hold the last slot)
  only that pending create can still be sent: the Create New Discounts card
  on Product Details reads "Confirm earlier discount" and explains why
  (`pendingDiscountCreateProvider`), and the form enables Save for the
  replay (`DiscountFormState.recoverable`). A fresh create stays blocked, also
  the edited offer after a refused replay. An uncertain write reads the list
  again, since the server may have committed it.
- A create the server accepted (success reply) whose result cannot be read
  (malformed, or for another product) is not confirmed and not replayed (a
  replay would return the same reply): it stays in the slot as committed
  (`pendingCommitted`), so no other create is sent. The form says it was
  most likely created; only the user's explicit "I checked the discounts:
  continue" releases it.
- The server keeps idempotency records 24 hours; sessions can last longer.
  After 23 hours a pending create is no longer replayed
  (`pendingExpired`): Save stays off until the user checks the product's
  discounts and explicitly discards it.
- `If-Match` with the discount `version` of a fresh read (the edit form and
  the details screen load `GET /discounts/{id}`; after a pause or resume the
  form continues with the version of the server's reply), never the ETag.
- `VERSION_CONFLICT` (412) is never retried. The form keeps the draft and
  the version it was based on, reads the latest discount and shows what
  changed (`DiscountConflictPanel`). Parts (value, schedule, repeat,
  minimum) only the server changed are taken over; parts both sides changed
  need Keep mine or Use saved. Only "Apply and review" moves the form onto
  the latest version (`DiscountMerge`); the user then saves again.
- Pause/resume are not archive: a paused discount keeps all values, stays
  editable and counts towards the limit; resume does not override the
  schedule (the server returns `active`, `scheduled` or `expired`). The
  edit form's status card has the Pause/Resume button
  (`DiscountFormController.toggle`): it confirms first, shares the form's
  busy state with Save and Archive (one write at a time, leaving blocked),
  keeps the entered values and shows the server's status only after it
  confirmed it. A conflict opens the form's conflict panel; an unconfirmed
  outcome never shows success.
- Field errors (`error.details[].field`, dotted paths) are shown on their
  input; whole-discount rules (`PRODUCT_NOT_DISCOUNTABLE`,
  `PRODUCT_PRICE_ZERO`, `DISCOUNT_LIMIT_REACHED`, `DISCOUNT_ARCHIVED`) have
  own texts; unknown codes show the server's display-safe message.
- The live preview is never authoritative; saved values come from the
  server reply.

## Deviations from the design

- Date and time use the Material date picker and the 24-hour time input,
  themed by `OrangeTheme`, instead of the custom calendar and spinner of the
  mock-ups.
- The design's "Bundle Quantity" label under Minimum Quantity is shown as
  "Minimum Quantity" (it is not a bundle).
- The Figma file was not inspected in this task; layouts follow the supplied
  screenshots.

## Tests

`test/features/discounts/` (draft validation and preview, contract mapping,
request headers and idempotency, screens: gating, overview, details actions,
form, offline) and `test/features/products/product_details_test.dart` (no
card without the capability).
