# Product discounts

Product discounts (Discount Overview, Discount Details, Create/Edit,
Pause/Resume, Archive) over the OrangeONE Mobile API **1.1.0** discount
endpoints of `mupi_mobile_pos_api` 19.0.2.2.0 with `mupi_product_discount`
19.0.1.0.0. Source of truth: `custom_addons/mupi_mobile_auth/doc/openapi.yaml`
and `custom_addons/mupi_product_discount/doc/api-schema.md` (revision 4) in
the addons repository.

## Availability

| Shop / user | Result |
|---|---|
| `GET /meta` without `product_discounts` (older addons, or updated addons without the discount addon) | No discount UI and no discount request; everything else unchanged |
| `product_discounts` listed, `discount_read` not granted | No discount UI |
| `discount_read` only | Read-only overview, list and details |
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
  presentation/providers/                list, details actions, form controllers
  presentation/pages/                    list, details, form
  presentation/widgets/                  summary card (Product Details), form sections
```

App composition (`product_dependencies.dart`) binds `discountRepositoryProvider`
to the v1 adapter (`ApiContract.mobileV1`: 1.1.0 is additive). The router
passes the product id and the product's `discount_manage` to the discount
pages (`DiscountScope`) and composes the summary card into Product Details
(`ProductDetailsPage.discountsBuilder`), so neither feature imports the
other's presentation. `ProductScaffold`, `ProductNavbar` and
`ProductActionSurface` moved to `shared/widgets` for that reason.

## Screens

| Route | Screen |
|---|---|
| `productDetails` | Summary card under the price: "Discount Overview" (total and up to four cards) or "Create New Discounts" |
| `productDiscounts` | "Discount Details" list: regular price, total, discounts with status pill, edit pencil and pause/resume switch (`OrangeSwitch`, on = not paused); sticky Create Discount |
| `productDiscountDetail` | One discount: value, server preview, schedule, timezone, repeat, minimum, status, applies now; Edit, Pause/Resume, Archive |
| `productDiscountForm` | Create (no `discount_id`) or Edit: live preview, Fixed Price / Percentage / Collective, Date & Time with No End Date, order Price card, Discount Preview, Discount Type (Lucide banknote / percent / package icons, the selected type's icon in front of its input), Date & Time and Minimum Quantity cards that open and close smoothly, Repeat Schedule; the start/end date opens a calendar card and the time a 24-hour wheel card (hour 00-23, minute 00-59), and Repeat Schedule a card with the options, all sliding up from the bottom (`discount_pickers.dart`); archive icon in the navigation bar in edit mode (`DELETE /discounts/{id}`); the shared Price card (`InfoRowCard.price`) shows the regular price, and its pencil (only with the product's `update_price`, online) opens `productPrice`; after a saved price the form reads the regular price again and keeps the typed values |

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
  - changed values: a created discount is edited with the changes
    (`createdMeanwhile`); a refused original lets the changed draft be
    created;
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
- The server keeps idempotency records 24 hours; sessions can last longer.
  After 23 hours a pending create is no longer replayed
  (`pendingExpired`): Save stays off until the user checks the product's
  discounts and explicitly discards it.
- `If-Match` with the discount `version` of a fresh read (the edit form and
  the details screen load `GET /discounts/{id}`; the list switch uses the
  version of the online list read), never the ETag.
- `VERSION_CONFLICT` (412) is never retried. The form keeps the draft and
  the version it was based on, reads the latest discount and shows what
  changed (`DiscountConflictPanel`). Parts (value, schedule, repeat,
  minimum) only the server changed are taken over; parts both sides changed
  need Keep mine or Use saved. Only "Apply and review" moves the form onto
  the latest version (`DiscountMerge`); the user then saves again.
- Pause/resume are not archive: a paused discount keeps all values, stays
  editable and counts towards the limit; resume does not override the
  schedule (the server returns `active`, `scheduled` or `expired`). The
  list switch (`DiscountToggleController`) confirms first, allows one write
  at a time, shows the server's reply in place and never moves before the
  server confirmed it.
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
