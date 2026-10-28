# Agent memory

The canonical instructions are in [AGENTS.md](AGENTS.md). Read that file and
README.md before changes. Keep project memory there to avoid conflicting copies.

Task 01 foundation: Flutter 3.47.5 / Dart 3.13.4, Very Good CLI 1.5.0;
Riverpod 3 with plain overrideable providers, GoRouter, and three native flavors.
Pair --flavor with lib/main_<flavor>.dart; bootstrap rejects mismatches.
CI uses Ubuntu 24.04 for offline unit/widget tests, formatting and analysis.
Native builds and device smoke tests must be verified separately from Dart tests.
Inventory features and Firebase remain deferred until requested.

Task 02 establishes the layer directories and core/shared ownership. The existing
initialization page now lives in presentation/pages. Follow the feature-first
section of AGENTS.md and docs/architecture.md; unused folders contain .gitkeep
only, with no generated business features or placeholder Dart implementations.

Task 03 adds initializationControllerProvider (auto-dispose AsyncNotifier) and a
shared environmentLoaderProvider callback dependency. Root scope remains in
bootstrap. Follow docs/state-management.md for provider conventions and tests;
configuration loading is local only, with explicit retry and safe error UI.

Task 04 adds the authentication feature, shared core Dio/SecretStore (now the Mobile API v2 client),
session-aware navigation and QR camera UI. Read docs/authentication.md before
changing auth: QR origins are validated dynamically (including ports), sessions retain their own origin, HTTP/HTTPS are supported in all flavors per user requirement,
and consumed challenges must never be replayed automatically. SessionController
is container-lived; logout/expiry clear secure storage. The previous initialization
page remains at /diagnostics/initialization. Home is a minimal signed-in destination,
not an implemented inventory dashboard. Never log or commit a token/QR payload.



Task 05 corrected feature ownership: features/home owns the scanner landing page,
camera page, lookup providers, domain contracts/entities/use case, and Odoo lookup
data layer. features/products owns independent details, permissions and name/price updates;
do not place scanner or lookup logic there. No product-information modal belongs
in the Home scanner. Follow the supplied landing/scanner designs. Completed lookups automatically open details or the prefilled draft.
The scanner resets on return; duplicate/concurrent lookups are suppressed.
App composition binds productRepositoryProvider at bootstrap using the current
secure session. Read docs/home-scanner.md. Add product remains a draft-only handoff
by explicit user instruction. Logout is in the Home wordmark's Account menu.

## Fixed navigation and glossy action cards

Every product-name card on every screen must show a stock badge, including price
update and future product workflows. Reuse `shared/widgets/stock_badge.dart` with
the current backend quantity and unit. Show In stock for positive quantities,
Out of stock for zero/negative quantities, and Stock unavailable when unknown;
never invent stock values. Keep the badge visible in each workflow state where
the product-name card is shown.

For future action-heavy screens, keep header navigation fixed and place primary
actions in a sticky bottom card; only the middle content scrolls. Follow this
convention unless the user or supplied design explicitly requests otherwise.

- Use 12 logical pixel top corners, clipped backdrop blur and subtle translucent
  white highlights for a clear, neutral glossy glass finish.
- Keep the entire action-card backing clear and neutral, with no orange gradient
  or colored tint. Brand gradients belong to buttons, not the glass surface.
- Preserve the buttons' specified brand colors: the primary action stays orange.
- Keep buttons at least 56 logical pixels tall and full-width on phones; use a
  side-by-side arrangement on wider screens when appropriate.
- Respect safe areas, readable contrast and permission/disabled states. Reserve
  space for the card so it never covers the final scrollable content.
- Keep pull-to-refresh; avoid redundant refresh buttons beneath the actions.
- Verify fixed header/action positions while scrolling, narrow and landscape
  layouts, enlarged text, and the rendered glass surface on a neutral backing.

Reference implementation:
`lib/features/products/presentation/widgets/product_action_surface.dart`.

Task 07 adds the dedicated protected Products price-update page. Read
`docs/product-price-update.md` before changing pricing: CHF is fixed; validate
integer hundredths; confirm before saving; recheck server permissions/current
price; use the supplied product `lst_price` endpoint (no invented pricelist API).
Successful responses return mapped products and refresh details. Uncertain writes
require a read before another submission, never automatic write retry. Reuse
`ProductActionSurface` for the clear-glass sticky actions.

Task 08 adds the protected Products Name & Tax edit page, opened by the details
header pencil. Read `docs/product-edit.md`. Use the combined products/update
endpoint with product:name_update; reference:read gates company tax options.
Omit tax_ids for name-only edits; [] explicitly removes all taxes. Preserve
multiple existing taxes until the user chooses a replacement. Never substitute
creation defaults for an existing product. Reuse ProductNameCard (stock badge),
ProductNavbar and ProductActionSurface in product workflows.

Task 09 adds Authentication SplashPage at /startup during actual session restore,
with accessible bouncing dots and no artificial delay. Read docs/splash-branding.md.
Use shared AppLogo and assets/branding/app_logo.png for application branding;
never tint or replace it with a tag. Run tool/sync_branding.ps1 after changing the
source PNG to update native launch copies, then rebuild Android/iOS launch assets.

Uniform branding: all orange screen/header/product-card/action-button fills use the exact
shared splash gradient in OrangeTheme.gradient. homeGradient/scannerGradient are
compatibility aliases, never separate designs. Generate matching native artwork
with `flutter test tool/generate_brand_background_test.dart` after theme changes.
The OS-controlled Android 12 splash permits a solid endpoint only; following
native/Flutter backgrounds use the shared gradient. See docs/brand-gradient.md.

Localization and login: the app supports English, Dutch, French, Italian,
Turkish and Tamil via the Very Good CLI l10n setup (`lib/l10n/arb`, generated
code is git-ignored). Add texts to all six ARB files and read them with
`context.l10n`; `test/l10n` fails when a language misses a message. The login
screen has the white `LanguageSelector` pill under the subtitle; the choice is
kept by `localeControllerProvider` (stored under `orangeone.locale` through
`SecretStore`, restored at startup, device language or English otherwise).
The QR scanner screen runs the camera only while `wifiConnectionProvider`
reports Wi-Fi; otherwise it shows "Please connect to the same Wi-Fi network as
the POS machine to scan the QR code." and starts again automatically when Wi-Fi
returns. Wi-Fi only reads the device's network, never claim it verifies that
the POS machine is on the same network. Widget tests that open the scanner must
override Wi-Fi (`test/support/wifi_fakes.dart`). Login, the QR scanner,
Barcode Home and the Barcode scanner screen are localized so far; see
docs/localization.md.

Recent scans: the barcode scanner's "Last scanned" card shows the latest found
product (name, category, barcode, stock, CHF price); the stored history of five
is unchanged. They are
stored in the session's EncryptedReadCache (`recordRecent`/`readRecents`, the
`\u0000recent` row), survive restarts, are deleted with the session and are
kept across product writes. Recording happens in `ProductLookupController.scan`
through `recentScansControllerProvider`; tapping an entry calls the same
`scan`. The "Powered By" footer is gone from Barcode Home. `App` keeps
`readCacheProvider` listened to so logout purges the cache immediately. See
docs/home-scanner.md and docs/offline-data.md.

Editing screens (Edit Name & Tax, Price, Stock, Creation): shared Product Details
name card with Category/Stock/Tax badges (no Tax badge on Details, no card on
Creation), cloud in the navigation bar, Save Changes -> confirmation -> toast on
Product Details (`productSuccessProvider`), category select/create
(`POST /categories`), default tax from `default_tax_ids`, optional price/stock
(empty stock = Not Set). No backend product name in UI text; "Powered By" only on
Login Home. See docs/product-edit.md and docs/product-creation.md.
