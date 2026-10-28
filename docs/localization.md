# Localization and the login language selector

## Languages

OrangeONE ships six languages: English (`en`, the template), Dutch (`nl`),
French (`fr`), Italian (`it`), Turkish (`tr`) and Tamil (`ta`). The app uses the
Very Good CLI / Flutter `gen-l10n` setup (`l10n.yaml`, `lib/l10n/arb/*.arb`,
generated code in the git-ignored `lib/l10n/gen/`). The leftover Spanish
template file was removed so that the supported set is exactly these six.

- Add or change text in `lib/l10n/arb/app_en.arb` (with a description), then
  the five other files. Run `flutter gen-l10n` (or any `flutter run`/`test`).
- Read text with `context.l10n` (`lib/l10n/l10n.dart`).
- `test/l10n/locale_controller_test.dart` checks that every language
  translates every message. The translations were written without a native
  review: have native speakers check them before release.

Localized so far: the Login home screen and the QR scanner screen, including the
camera status and permission messages of `QrCamera`. Other screens, Odoo error
messages (`AppFailure.message` from the server) and the CodeCamera used by the
product scanner remain English; the product scanner keeps its English
defaults via `CodeCameraMessages`. Sending `Accept-Language` to the API
(localized server messages and product names) is not implemented.

## Language selector

`LanguageSelector` (`features/authentication/presentation/widgets`) is the white
pill under the login subtitle. It shows a greeting in the current language
(Hello, Hallo, Bonjour, Ciao, Merhaba, வணக்கம்); tapping it opens a menu of the
six greetings. A choice applies immediately to the Login and QR scanner
screens. The visible pill is 40 points high inside a 48 point touch target;
screen readers announce "Language: <name>" and read the menu entries by the
language's own name (English, Nederlands, Français, Italiano, Türkçe, தமிழ்).

## Persistence and fallback

`LocaleController` (`lib/l10n/locale_controller.dart`, `localeControllerProvider`)
keeps the selected `Locale`. `App` passes it to `MaterialApp.router(locale:)`.

- Stored as the language code under `orangeone.locale` through the existing
  injectable `SecretStore` (platform secure storage). The language is not a
  secret, but this reuses an existing, tested dependency instead of adding a
  preferences package. Logout and expiry do not clear it.
- Restored at startup while the session restore runs. A selection made while
  restoring wins; unsupported or corrupt stored values are ignored.
- Without a choice the device language is used when supported, otherwise
  English. A storage failure never blocks the app: the language then applies
  until the next restart.

## QR scanner and Wi-Fi

The scanner only runs while the device reports a Wi-Fi connection
(`core/network/wifi_connection.dart`, `wifiConnectionProvider`, based on
`connectivity_plus`; the existing product-cache connectivity stream is
separate).

| Wi-Fi state | Scanner screen |
| --- | --- |
| Reading | Progress indicator, "Checking Wi-Fi…", no camera |
| Off or unreadable | No camera is created; Wi-Fi-off icon, the message "Please connect to the same Wi-Fi network as the POS machine to scan the QR code." (announced as a live region) and "Scanner off · Wi-Fi required" |
| On | Camera and instructions as before |

When Wi-Fi returns the camera starts again automatically with a fresh status;
when it drops the camera is released. Sign-in failures, a sign-in in progress
and the "Scan a new QR code" action keep their precedence over the Wi-Fi
message. The QR authentication flow is unchanged.

**Limitation:** the check reads the device's network interface only. It cannot
know which Wi-Fi network is connected or whether the POS machine is reachable
or on the same network, so the app never claims the network is verified. The
message asks the user to connect; a different network still fails at sign-in
with the existing error handling. Ethernet, mobile data and VPN-only
connections count as "not Wi-Fi"; Wi-Fi with a VPN counts as Wi-Fi.

## Tests

- `test/features/authentication/presentation/language_selector_test.dart`:
  pill, menu, all six languages on both screens, persistence across a restart,
  device-language fallback, accessibility labels, 320x568 layout.
- `test/features/authentication/presentation/qr_wifi_test.dart`: scanner off
  and on, repeated Wi-Fi cycles, unreadable state, unchanged sign-in.
- `test/core/network/wifi_connection_test.dart`: mapping of platform networks.
- Widget tests that open the QR scanner override the Wi-Fi state with
  `test/support/wifi_fakes.dart`; no plugin or real network is involved.
