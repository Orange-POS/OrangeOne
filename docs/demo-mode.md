# Demo Mode

Demo Mode lets App Review (and anyone without a POS) explore every product
screen offline with sample data. It is built into every flavor
(`lib/features/demo`); there is no Remote Config and no build flag.

## Behavior

1. **Settings** (gear on the login screen, all flavors) has a **Demo Mode**
   switch. Off at every launch: it is never persisted and nothing starts it
   but the user. The Crashlytics tools inside Settings stay development-only.
2. Switching it on does **not** sign in. The normal QR login is next: its
   **Scan QR code** screen shows **sample QR codes** instead of the camera
   (no camera, Wi-Fi, network or server is needed):
   - *Store manager* – looks up and edits products, changes prices, counts
     stock, creates products and categories.
   - *Read-only counter* – looks up products; every restricted action is
     disabled like a user without permissions.
3. Choosing one opens the normal navigation (Home → scanner → details → edit,
   price, stock) with sample data. The scanner lists the **sample barcodes**
   (tap = the normal lookup), the **Demo Mode banner** is shown on every
   screen, and its **Settings** button opens the switch.
4. **Logout** leaves the sample session and discards its changes, recent scans
   and success toast; Demo Mode stays on for another sample login, which
   starts from the same sample data. Turning the switch off ends Demo Mode
   and returns to the normal login. A restart always starts in normal mode.
5. The switch is disabled while a real session exists or is being restored.

## Isolation

- `demoModeProvider` (switch) and `demoLoginProvider` (sample sign-in) are
  independent of `sessionControllerProvider`, `SecretStore`, Dio, the
  encrypted read cache and the Crashlytics identity (`activeSessionProvider`
  stays null).
- `lib/app/providers/product_dependencies.dart` selects the demo repositories
  (`DemoProductRepository`, `DemoProductDetailsRepository`, in-memory recent
  scans over a fresh `DemoCatalog`) only while `demoLoginProvider` is set.
  Otherwise nothing changes, and a missing session still fails as before.
- `authenticationRedirect(demo: true)` treats a demo sign-in as signed in.
- Product versions behave like the backend (`VERSION_CONFLICT` on stale
  edits); the preview of stock changes uses the same use cases as production.

Product history is not part of the app yet, so the demo has none.
