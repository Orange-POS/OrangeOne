# Help & Support (tutorial videos)

Settings › Help & Support › **OrangeOne Tutorial** opens the **Tutorial**
screen (`/settings/tutorial`, route `tutorial`). It lists the published YouTube
guides from Cloud Firestore, so videos can be added, changed, reordered,
unpublished or removed in the Firebase console without an app release.

The feature lives in `lib/features/help_support` and is built to grow into a
full shop support area (more sections, resources and categories):

| Layer | Contents |
| --- | --- |
| `domain` | `TutorialVideo` (validated YouTube video ID, canonical watch link), `LocalizedText`, `TutorialCatalog`, `TutorialRepository` |
| `data` | `tutorialFromDocument` (untrusted document → entity), `FirestoreTutorialRepository`, `UnavailableTutorialRepository` |
| `presentation` | `TutorialPage`, `TutorialVideoCard`, providers (`tutorialCatalogProvider`, `tutorialVideoOpenerProvider`) |

Settings only navigate to the route; the shared `PanelScaffold` gives both
screens the same header and panel. Opening apps goes through the injectable
`ExternalLauncher` (`lib/core/platform`, `url_launcher`).

## Behavior

- The screen listens to Firestore while it is open (live updates) and stops
  when it closes. Firestore keeps the last result on the device, so tutorials
  seen once stay visible offline.
- The query asks only for `published == true` (what the rules allow); the app
  sorts by `sortOrder`. A published document without `sortOrder` is therefore
  still shown (last) instead of disappearing, and no composite index is needed.
- Each video is a vertical card: the thumbnail (2:1) with the YouTube badge,
  then the title, the full description and **Watch video**. Titles and
  descriptions are never shortened; the card grows with them. On tablets the
  cards stay at most 560 pt wide.
- **Watch video** (the whole card) opens
  `https://www.youtube.com/watch?v=<id>` only in a non-browser app, which is
  the YouTube app (`LaunchMode.externalNonBrowserApplication`). The video never
  plays inside OrangeONE. Without the YouTube app a message offers **Open in
  browser**; the browser opens only when the user chooses it.
- Managed data is untrusted. Only an 11-character YouTube video ID is kept
  (`youtubeVideoId` may also hold a `youtube.com/watch`, `youtu.be`, `shorts`,
  `embed` or `live` link); thumbnails must be `https`, otherwise YouTube's own
  preview is used.
- `language`: the app shows the videos in the app language plus videos without
  a language; without any in that language, the English ones; and never hides
  every video because of the language. Titles and descriptions may also be a
  map of language code → text.
- `category` is read and kept for a future support library; not shown yet.
- Demo Mode, sign-in and the POS workflows are unchanged; the screen is
  reachable signed in or out, like Settings.

## States and error reporting

| Situation | Screen | Crashlytics |
| --- | --- | --- |
| Published videos | the list | — |
| No published document | "No tutorials are available yet." | not reported |
| Offline, never loaded | "Connect to the internet to load the tutorials." + Try again | not reported |
| Published documents, none usable (no title, no valid `youtubeVideoId`) | "The tutorials could not be loaded. (Ref: OO-…)" + Try again | reported |
| Some documents unusable | the usable videos | reported |
| A video without `sortOrder` | shown last | reported |
| Firestore error (rules, index, server) | load error with `(Ref: OO-…)` + Try again | reported |
| No Firebase configuration (local builds) | load error | not reported (no Crashlytics) |

Reports reuse the app's existing `CrashReporter.recordFailure` with the
operation `FIRESTORE support_videos`, the existing failure kinds and policy
(`docs/firebase-crashlytics.md`) and the `OO-` error reference:

- Data problems: kind `protocol`, code `MISSING_TITLE`, `INVALID_VIDEO_ID` or
  `MISSING_SORT_ORDER`; each code once per screen visit (not per snapshot).
- Firestore errors keep their code as `FIRESTORE_<CODE>`: `permission-denied`,
  `unauthenticated`, `failed-precondition`, `invalid-argument`, `not-found`
  → `configuration` (always); `unavailable` → `network` and
  `deadline-exceeded` → `timeout` (throttled); `cancelled` and
  `resource-exhausted` → never reported; anything else → `backend` (always).
  Try again reports a persisting error again, like a repeated API call.
- No document content, title, link or ID is sent; the code says which field
  is wrong. DEV and STG report to the Development project (`environment` key
  tells them apart), PROD to the Production project.

## Environments

Firestore uses the Firebase project of the build, which CI already selects per
flavor (`docs/firebase-crashlytics.md`): **DEV and STG** read the Development
project, **PROD** the Production project. No GitHub variable, secret or
workflow changes. Videos must be published in each project separately (for
example test in Development, then add to Production).

## Firestore data (existing schema)

Collection `support_videos`, one document per video (for example
`getting-started-001`):

| Field | Type | Required | Example |
| --- | --- | --- | --- |
| `title` | string (or map of language → string) | yes | `Getting started` |
| `description` | string (or map) | no | `Learn how to manage product stock in OrangeOne.` |
| `category` | string | no | `basics` |
| `language` | string | no | `en` (empty = every language) |
| `published` | boolean | yes | `true` shows it, `false` hides it |
| `sortOrder` | number | yes | `1`, `2`, `3` … (lower first) |
| `youtubeVideoId` | string | yes | `dQw4w9WgXcQ` (or a YouTube link) |
| `thumbnailUrl` | string (`https`) | no | empty or invalid = YouTube preview |

Publish/unpublish = toggle `published`; reorder = change `sortOrder`; remove =
delete the document or set `published` to `false`. Changes appear on open
screens within seconds.

## Firebase console setup (owner, manual)

Repeat for `orangeone-development` and `orangeone-production`:

1. **Firestore Database › Create database**: Standard edition, production
   mode, a European location (for example `europe-west6`, Zürich).
2. **Rules**: the content of
   [`firebase/firestore.rules`](../firebase/firestore.rules), **Publish**. They
   allow reading published support videos only; the app cannot write.
3. **Indexes**: no composite index is needed (the query filters on
   `published` only; Firestore's automatic single-field index serves it, and
   [`firebase/firestore.indexes.json`](../firebase/firestore.indexes.json) is
   empty). An existing `published + order` index is unused and can be deleted.
   Do not delete or disable the automatic single-field indexes.
4. **Data**: collection `support_videos`, one document per video with the
   fields above.
5. Open Settings › OrangeOne Tutorial on a CI-built app of that environment
   and check the list and **Watch video**.

## Not verified

Firestore in the real Development/Production projects, the rules,
opening the YouTube app on Android and iOS, and the iOS build of
`cloud_firestore` and `url_launcher` need a CI build and a device.
