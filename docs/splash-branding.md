# Startup splash and shared branding (Task 09)

The Authentication feature owns `SplashPage` and `BouncingDots`. The app starts
at the named startup route while the existing SessionController restores secure
session state. A valid session routes to Home; an absent or invalid session goes
to Login. Restore failures leave the splash and show the existing safe error and
retry action. No extra session requests, credentials, timer-based navigation or
artificial minimum splash duration were added.

Three white dots bounce with staggered phases while Flutter is waiting. The
animation stops for the system reduced-motion setting and is disposed with its
widget. The screen supports safe areas, enlarged text and scrolling on short
screens. Its gradient, name and tagline follow the supplied PNG/SVG. Figma MCP
access remained blocked by its plan limit, so direct Figma fidelity is unverified.

## Central asset

`assets/branding/app_logo.png` is the unmodified user-supplied logo (118×120).
`shared/widgets/app_logo.dart` owns its rendering, preserving colors and aspect
ratio on a white backing for contrast. BrandMark uses it on Login and Home;
product name cards also use it. Functional discount/tag icons retain their meaning.
Larger artwork will retain the resolution limits of this supplied source.

Native launch assets are copies of this source. After replacing the central PNG,
run `tool/sync_branding.ps1` and rebuild the app. A test checks that every native
copy matches the central source. Flutter hot reload alone cannot update native
launch resources.

## Native handoff

Android launch drawables use an orange gradient with the supplied logo, including
day/night variants. Android 12+ uses the OS-mandated solid splash background and
centered logo. NormalTheme also has an orange backing while Flutter initializes.
The iOS launch storyboard uses the exported shared gradient and centered supplied
logo. See [uniform branding](brand-gradient.md) for regeneration and platform limits.

Native launch screens are static by platform design. Bouncing dots start with
Flutter's first frame. Native launch appearance cannot be identical across these
platforms; the animated Authentication page is the shared designed experience.
Launcher/home-screen app icons are outside this task's launch-screen changes.

## Checks

Tests cover staggered movement, reduced motion, restored/no-session routing,
restore failure, enlarged text and native asset consistency. Existing auth,
navigation, product and API tests continue to use controlled dependencies.
On 16 October 2026, all 273 unit/widget tests passed, strict analysis passed and
the splash was rendered and visually inspected at 390×844 with the decoded logo.
Enlarged-text layouts passed at 320×568, 390×844 and 844×390. The iOS launch
storyboard parses as XML; that does not confirm an iOS build or rendered launch.
The controlled Android integration journey passed on SM A315F: the splash remains
visible during a held session restoration, then login, scan, product operations,
back navigation and logout complete successfully. Android native launch resources
compiled successfully as part of that build.
On 17 October 2026, the completed normal development APK was installed and
launched again on SM A315F after resuming the task.
iOS compilation and native visual verification require macOS/an iOS device.
