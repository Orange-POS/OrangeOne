# Consistent orange branding

The splash's existing gradient is now the shared `OrangeTheme.gradient`:
`#BE4602` → `#FF8A33`, begin `(-.54, -.72)`, end `(1, .6)`, stops `.08/.94`.
The former Home and scanner definitions are aliases of that same constant.

Login, Home, QR/scanner headers, product details, edit and pricing pages use this
definition. Product-name cards no longer define their own orange gradient.
Buttons use the supplied solid-color component, independent of the background gradient: #F56600 normal/loading/Done, #C84E00 pressed/hover, #DADCE0 disabled with #5F6368 labels. Primary labels are white; outlined buttons have white fill and matching state-colored text/border. No button gradient, scrim or text halo.
Sticky action cards use clear neutral glass without an orange backing. They retain
backdrop blur, white highlights, 12px top corners, large fixed actions and safe-area
spacing. Button colors remain independent of the branded background; theme changes must not tint glass.
Readable small accents use the dark endpoint rather than unrelated orange shades.
The supplied logo artwork and semantic success/error colors remain independent.

System bars are styled at app composition so a splash-specific solid navigation
bar color does not persist onto later screens. Native platform versions may still
apply their own system-bar treatment.

## Native launch

Run `flutter test tool/generate_brand_background_test.dart` after changing the
shared gradient. This renders the Flutter shader to native launch PNGs and writes
the Android solid fallback from the same palette. The exported source is
`assets/branding/launch_gradient.png`; Android and iOS copies are checked by tests.
Android legacy launch and NormalTheme use it; the iOS launch storyboard stretches
the same artwork behind the logo. Native aspect-ratio scaling follows the platform.

Android 12+ enforces a solid OS splash background. Its generated dark endpoint is
the closest supported handoff; it cannot display the full linear gradient during
that OS-controlled interval. Flutter's following splash uses the exact gradient.
iOS launch changes require macOS/device verification.

Feature business logic, API calls, routing guards, permissions and save semantics
are unchanged. Theme and reusable presentation infrastructure stay in shared/app;
features continue to own their pages and workflows.

Verification: the full 275-test regression run passed. Focused UI checks also
cover gradient-enabled buttons, disabled interaction, fixed footers and responsive
product pages (22 focused checks passed after the footer refinements). Native
export consistency and opaque disabled fills are tested. Six screens were rendered
and visually reviewed, and strict analysis/formatting passed. The final Android
development APK built successfully and was installed on the Android phone. Launch
logs showed Flutter initialization, but sustained device execution and live debugger
reconnection were not confirmed at handoff. iOS compilation remains unverified on
Windows.


