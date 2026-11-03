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
  seen once stay visible offline. Never-loaded + offline shows "Connect to the
  internet…", no published video shows "No tutorials are available yet.", and
  a failure (no Firebase configuration, missing rules or index) shows an error
  with **Try again**. Nothing else in the app depends on Firestore.
- **Watch video** (the whole card) opens
  `https://www.youtube.com/watch?v=<id>` only in a non-browser app, which is
  the YouTube app (`LaunchMode.externalNonBrowserApplication`). The video never
  plays inside OrangeONE. Without the YouTube app a message offers **Open in
  browser**; the browser opens only when the user chooses it.
- Managed data is untrusted. Only an 11-character YouTube video ID is kept
  (from an ID or a `youtube.com/watch`, `youtu.be`, `shorts`, `embed` or `live`
  link); any other link is skipped. Thumbnails must be `https`, otherwise
  YouTube's own preview is used. Invalid documents are skipped, not shown.
- Titles and descriptions may be one text or one text per language code
  (`en`, `nl`, `fr`, `it`, `tr`, `ta`); the app language is used, then English,
  then any given text.
- Demo Mode, sign-in and the POS workflows are unchanged; the screen is
  reachable signed in or out, like Settings.

## Environments

Firestore uses the Firebase project of the build, which CI already selects per
flavor (`docs/firebase-crashlytics.md`): **DEV and STG** read the Development
project, **PROD** the Production project. No GitHub variable, secret or
workflow changes; Crashlytics is untouched. Videos must be published in each
project separately (for example test in Development, then add to Production).

## Firestore data

Collection `support_videos`, one document per video (document ID is free, for
example `adjust-stock`):

| Field | Type | Required | Example |
| --- | --- | --- | --- |
| `title` | string, or map of language → string | yes | `How to Adjust Stock` or `{ "en": "How to Adjust Stock", "nl": "Voorraad aanpassen" }` |
| `description` | string or map | no | `Learn how to manage product stock in OrangeOne.` |
| `youtube_url` | string | yes | `https://www.youtube.com/watch?v=VIDEO_ID` or `https://youtu.be/VIDEO_ID` |
| `thumbnail_url` | string (`https`) | no | empty = YouTube preview |
| `published` | boolean | yes | `true` shows it, `false` hides it |
| `order` | number | yes | `10`, `20`, `30` … (lower first; documents without it are not listed) |

Publish/unpublish = toggle `published`; reorder = change `order`; remove =
delete the document or set `published` to `false`. Changes appear on open
screens within seconds.

## Firebase console setup (owner, manual)

Repeat for `orangeone-development` and `orangeone-production`:

1. **Firestore Database › Create database**: Standard edition, production
   mode, a European location (for example `europe-west6`, Zürich). The
   location cannot be changed later.
2. **Rules**: replace the rules with the content of
   [`firebase/firestore.rules`](../firebase/firestore.rules) and **Publish**.
   They allow reading published tutorials only; nothing can be written by the
   app.
3. **Indexes › Composite › Create index**: collection `support_videos`, fields
   `published` Ascending and `order` Ascending, query scope Collection
   (also in [`firebase/firestore.indexes.json`](../firebase/firestore.indexes.json)).
   Wait until it is *Enabled*. Without it the screen shows the load error.
4. **Data › Start collection** `support_videos`, then add one document per video
   with the fields above.
5. Open Settings › OrangeOne Tutorial on a CI-built app of that environment
   and check the list and **Watch video**.

With the Firebase CLI the same files can be deployed instead:
`firebase deploy --only firestore:rules,firestore:indexes --project <project-id>`
(after adding a `firebase.json` that points to them; not part of this repo).

## Not verified

Firestore in the real Development/Production projects, the rules and index,
opening the YouTube app on Android and iOS, and the iOS build of
`cloud_firestore` and `url_launcher` need a CI build and a device.
