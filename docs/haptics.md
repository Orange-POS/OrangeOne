# Haptic feedback

The app plays a short haptic at a few meaningful moments. It is centralized:
screens never call `HapticFeedback` themselves.

| Effect (`HapticEffect`) | When | Played from |
|---|---|---|
| `scan` (selection click) | The camera accepted a code (product scanner and QR login) | `CodeCamera` (`shared/widgets/code_camera.dart`) |
| `confirm` (light impact) | Confirm in a change's confirmation dialog (Cancel is silent) | `ConfirmDialog` (`shared/widgets/confirm_dialog.dart`), used by every product and discount confirmation |
| `success` (medium impact) | The server confirmed a product or discount change | `ProductSuccessController.show` (product forms and discount results on Product Details), `showDiscountResult` (pause/resume on the discount screens) |
| `selection` (selection click) | The time picker's hour, minute or AM/PM wheel moved to another value (scroll or chevron) | `DiscountNumberWheel.onSelectedItemChanged` |
| `error` (iOS: system error pattern; Android: heavy tap) | Validation refused the entered values: an input's error appeared, or the server refused a save as invalid | `ValidationHaptic` (shared), `DiscountSection`, `HapticsController.rejected` in the form controllers |

Notices (offline, read-only, permission), network and other failures and
ordinary taps have no haptic.

### Error haptic: when exactly

- Inputs with inline validation are wrapped in `ValidationHaptic`
  (`shared/widgets/validation_haptic.dart`): product name, price, stock
  (Edit, Create, Update Price, Update Stock) and every discount number
  input (`DiscountTextField`). It plays only when the error changes from
  none to shown. A screen that opens with an error, a rebuild, or typing on
  in a still-invalid value (even if the message changes) stays silent; once
  fixed, a new error plays again.
- The discount form cards (Date & Time, Minimum Quantity, Repeat Schedule)
  do the same for their own error (`DiscountSection`), but not when the
  error only moves between the closed card and its opened input.
- A save refused by the server as invalid (`FailureKind.validation`) plays
  it through `HapticsController.rejected(error)` in the four product form
  controllers and the discount form (`_failed`). Other failure kinds never
  do.
- Validation rules, messages and when they show are unchanged.

### No repeated vibrations

`HapticsController.minimumGap` holds back a repeat of the same effect:
`selection` at most every 40 ms (a fast wheel spin still ticks per value
without buzzing), `error` at most once a second (an input error and the
refused save behind it vibrate once). The gaps use a monotonic clock
(`hapticClockProvider`), so a change of the device time never holds haptics
back. The wheels tick only on a value change, never on a rebuild or when
the 12-/24-hour switch rebuilds them.

## Code

`core/platform/haptics.dart`:

- `HapticEngine` / `PlatformHapticEngine` (`hapticEngineProvider`): the
  platform's `HapticFeedback`, replaced by `RecordingHapticEngine`
  (`test/support/haptics_fakes.dart`) in tests. The error uses
  `errorNotification` on iOS; Android's equivalent (`REJECT`) needs API 30,
  so Android plays `heavyImpact`, available on every supported version.
- `HapticsController` (`hapticsControllerProvider`): on by default; the
  Settings switch "Haptic feedback" turns it off (all effects, including
  the new ones). The choice is stored under `orangeone.haptics` in the
  injectable `SecretStore` (as the language and time format) and restored
  at start; the first effect after a start waits for that read. A storage
  failure keeps the choice for the current run. `play` never throws (a
  device without haptics stays silent).
- `playHaptic(context, effect)`: for widgets; silent without a provider
  scope.

Android and iOS also skip haptics when touch feedback is off in the phone's
own settings. New screens get haptics through the shared dialogs, success
toast, camera, wheels and `ValidationHaptic`; add a new `HapticEffect` only
for a new kind of moment, never per screen.

## Tests

`test/core/platform/haptics_test.dart` (preference, failures, platform
calls, gaps, `rejected`), `test/shared/validation_haptic_test.dart` (error
transitions, form cards), `test/app/haptics_hooks_test.dart` (shared hook
points, Cancel silent, switched off),
`test/features/discounts/discount_screens_test.dart` (time card wheels,
discount input error), the product controller tests (server validation
vibrates, network failure does not) and
`test/features/settings/settings_haptics_test.dart` (switch, persistence,
translations). Controller tests that run without the Flutter binding use
`hapticsOverrides()`. The vibration itself is checked on a device only.
