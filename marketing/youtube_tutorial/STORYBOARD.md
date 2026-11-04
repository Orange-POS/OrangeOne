# Getting Started with OrangeOne — Storyboard

YouTube tutorial, 16:9, 1920 × 1080, 30 fps, 2:04, H.264 + AAC stereo
(loudness −14 LUFS). Thumbnail 1280 × 720 PNG.

**Production flavor only.** Screens were captured from the real app with the
Production environment: no development diagnostics, crash tools, Settings,
Demo Mode or banner appear. Product data is a fictional in-memory catalog.

**Branding.** Titles say "OrangeOne". The supplied logo artwork contains the
misspelled "Orrange ONE" line, so the video, thumbnail and the in-app
screenshots use a text-free crop of the logo's POS mark (`brand/`). The app's
own "OrangeONE" wordmark next to the logo is shown unchanged in screenshots.

**Layout.** Brand gradient background (`OrangeTheme.gradient`). Left: logo +
series title, chapter chip, chapter title, one short instruction line, and
a six-segment progress bar. Right: phone mockup with the real screens, touch
indicators, scan lines, spotlight highlights and gentle zooms.

| Time | Section | Screens | On-screen text | Motion & sound |
|------|---------|---------|----------------|----------------|
| 0:00–0:07 | Intro | — | **Getting Started with OrangeOne** · A quick tour for new users | Logo pops in (ease-out-back), title letters stagger in. Music fades in, soft riser. |
| 0:07–0:15 | Before you start | — | The login QR code on your POS · Wi-Fi on the same network as the POS | Two cards rise in. |
| 0:15–0:35 | **1 Sign in** | login → qr_scan → qr_signing → home | Open the login QR code on your POS. → Tap **Tap to scan QR** and point the camera at it. → You are signed in securely. → Welcome to **Home**. | Phone slides in (whoosh). Zoom + tap (click). Push (whoosh). Scan line, detection flash (scan beep). Fade to Home (chime). |
| 0:35–0:50 | **2 Scan a product** | home → scanner → details | Tap the **scan button**. → Point at the barcode. It scans by itself. → The product opens right away. | Zoom + tap, push, laser line over the product label, flash + beep, push to details. |
| 0:50–1:03 | **3 Product details** | details | Name and category. → Current stock. → Assigned tax. → Price in CHF. → Pencil icons open the editors. | Zoom in; spotlights with labels (soft pop each). |
| 1:03–1:20 | **4 Edit name & tax** | details → edit → typing ×3 → tax sheet → filled → confirm → details + toast | Tap the **pencil** next to the name. → Type the new name. → Pick the tax. → **Save Changes**, then **Confirm**. → Saved. The message shows what changed. | Taps, key clicks while typing, sheet/dialog fades, zoom on Save, pop back, zoom on toast (chime). |
| 1:20–1:34 | **5 Update the price** | details → price → typing ×3 → confirm → details + toast | Tap the **pencil** next to Price. → Enter the new price. → Check it, then **Confirm**. → Price updated. | Same pattern; CHF 1.20 → 1.50. |
| 1:34–1:50 | **6 Update stock** | details → stock → Add → typing ×2 → scroll → confirm → details + toast | Tap the **pencil** next to the stock. → Choose **Update**, **Add** or **Remove**. → Enter the quantity. → Preview the new stock. → Confirm the change. → Stock updated. | Add 24 units; swipe gesture scrolls the form to the live preview `120 + 24 = 144 Units` (spotlight); 120 → 144 Units. |
| 1:50–1:56 | Keep going | details → home | Tap **Open Scanner** for the next product. → Log out from **Home** when you are done. | Spotlights on Open Scanner and the Home logout button. |
| 1:56–2:04 | Outro | — | **You're all set!** · Scan · Check · Update — with OrangeOne | Phone slides away, logo + title, riser; music fades out. |

## Accuracy notes

- Every phone frame is a screenshot of the current app (capture harness),
  following real navigation: scan → Product Details; each editor goes Save
  → confirmation → Confirm → Product Details with the success message.
- The Home → Details step in "Keep going" is a cross-fade between two real
  screens (Open Scanner → back), not a single tap.
- Camera previews (POS QR code, product label) are illustrations because a
  test cannot use a camera; the QR pattern encodes nothing.
- No on-screen keyboard is drawn; typing shows the field contents changing.
- Left out on purpose: the language menu (the test renderer has no Tamil
  font, so one entry would show boxes) and the scanner's "Last scanned" card
  after editing (it keeps the product as scanned, which reads like stale data
  in a tutorial).
