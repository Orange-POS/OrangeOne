// "Getting Started with OrangeOne" — scene data (1920 x 1080, ~2 minutes).
//
// Edit this file to change timing, text or the order of screens; engine.js
// only interprets it. Times are seconds. Positions are logical app pixels
// (390 x 844), the same units as shots/manifest.json.
//
// screens:    { t, shot, tr }  tr = push | pop | fade | modal | cut | scroll
// taps:       { t, target }    target = manifest target name or {x,y,w,h}
// zooms:      { t, s, x, y }   camera keyframes (eased between keyframes)
// highlights: { t0, t1, rect|target, label, below }
// scans:      { t0, t1, rect, flash }
// chapters:   { t0, t1, n, title }      left panel heading + progress bar
// captions:   { t0, t1, text }          one short line under the heading
// sfx:        extra sound cues; taps, transitions, typing, scans and
//             success toasts get their sounds automatically.

window.TIMELINE = {
  duration: 124,
  fps: 30,
  phoneIn: 14.6,
  phoneOut: 116.0,

  screens: [
    { t: 0, shot: 'login', tr: 'cut' },
    // 1 Sign in
    { t: 20.2, shot: 'qr_scan', tr: 'push' },
    { t: 25.0, shot: 'qr_signing', tr: 'fade' },
    { t: 27.4, shot: 'home', tr: 'fade' },
    // 2 Scan
    { t: 37.8, shot: 'scanner', tr: 'push' },
    { t: 43.0, shot: 'details', tr: 'push' },
    // 4 Edit name & tax
    { t: 64.4, shot: 'edit', tr: 'push' },
    { t: 66.4, shot: 'edit_type_0', tr: 'cut' },
    { t: 67.0, shot: 'edit_type_1', tr: 'cut' },
    { t: 67.7, shot: 'edit_type_2', tr: 'cut' },
    { t: 69.6, shot: 'edit_tax_sheet', tr: 'modal' },
    { t: 71.2, shot: 'edit_filled', tr: 'modal' },
    { t: 73.4, shot: 'edit_confirm', tr: 'modal' },
    { t: 75.6, shot: 'details_after_edit', tr: 'pop' },
    // 5 Price
    { t: 81.2, shot: 'price', tr: 'push' },
    { t: 83.2, shot: 'price_type_0', tr: 'cut' },
    { t: 83.7, shot: 'price_type_1', tr: 'cut' },
    { t: 84.2, shot: 'price_type_2', tr: 'cut' },
    { t: 86.2, shot: 'price_confirm', tr: 'modal' },
    { t: 88.4, shot: 'details_after_price', tr: 'pop' },
    // 6 Stock
    { t: 95.2, shot: 'stock', tr: 'push' },
    { t: 97.6, shot: 'stock_add', tr: 'cut' },
    { t: 99.3, shot: 'stock_type_0', tr: 'cut' },
    { t: 99.8, shot: 'stock_type_1', tr: 'cut' },
    { t: 101.0, shot: 'stock_preview', tr: 'scroll', scroll: { d: 65, top: 127, bottom: 743 } },
    { t: 104.0, shot: 'stock_confirm', tr: 'modal' },
    { t: 106.2, shot: 'details_after_stock', tr: 'pop' },
    // Wrap-up: next product, log out
    { t: 113.0, shot: 'home', tr: 'fade' },
  ],

  taps: [
    { t: 20.0, target: 'login_scan' },
    { t: 37.6, target: 'home_scan' },
    { t: 64.2, target: 'details_edit' },
    { t: 65.9, target: 'edit_name' },
    { t: 69.4, target: 'edit_tax' },
    { t: 71.0, target: 'edit_tax_option' },
    { t: 73.2, target: 'edit_save' },
    { t: 75.4, target: 'edit_confirm' },
    { t: 81.0, target: 'details_price' },
    { t: 82.8, target: 'price_input' },
    { t: 86.0, target: 'price_save' },
    { t: 88.2, target: 'price_confirm' },
    { t: 95.0, target: 'details_stock' },
    { t: 97.4, target: 'stock_add' },
    { t: 98.9, target: 'stock_input' },
    { t: 103.8, target: 'stock_save' },
    { t: 106.0, target: 'stock_confirm' },
  ],

  swipes: [{ t0: 100.8, t1: 101.6, from: { x: 300, y: 690 }, to: { x: 300, y: 600 } }],

  zooms: [
    { t: 0, s: 1, x: 195, y: 422 },
    { t: 18.0, s: 1, x: 195, y: 358 },
    { t: 19.0, s: 1.22, x: 195, y: 358 },
    { t: 20.3, s: 1.22, x: 195, y: 358 },
    { t: 21.2, s: 1.18, x: 195, y: 399 },
    { t: 24.8, s: 1.18, x: 195, y: 399 },
    { t: 25.6, s: 1, x: 195, y: 422 },
    { t: 36.0, s: 1, x: 195, y: 395 },
    { t: 36.9, s: 1.22, x: 195, y: 395 },
    { t: 37.9, s: 1.22, x: 195, y: 395 },
    { t: 38.8, s: 1.2, x: 195, y: 408 },
    { t: 42.7, s: 1.2, x: 195, y: 408 },
    { t: 43.4, s: 1, x: 195, y: 422 },
    { t: 50.4, s: 1, x: 195, y: 422 },
    { t: 51.2, s: 1.2, x: 195, y: 330 },
    { t: 57.6, s: 1.2, x: 195, y: 330 },
    { t: 58.4, s: 1.2, x: 195, y: 525 },
    { t: 60.6, s: 1.2, x: 195, y: 525 },
    { t: 61.4, s: 1, x: 195, y: 422 },
    { t: 72.4, s: 1, x: 195, y: 781 },
    { t: 73.0, s: 1.25, x: 195, y: 781 },
    { t: 73.6, s: 1.25, x: 195, y: 781 },
    { t: 74.3, s: 1, x: 195, y: 500 },
    { t: 76.2, s: 1, x: 195, y: 600 },
    { t: 76.9, s: 1.25, x: 195, y: 600 },
    { t: 79.0, s: 1.25, x: 195, y: 600 },
    { t: 79.8, s: 1, x: 195, y: 422 },
    { t: 85.2, s: 1, x: 195, y: 781 },
    { t: 85.8, s: 1.25, x: 195, y: 781 },
    { t: 86.4, s: 1.25, x: 195, y: 781 },
    { t: 87.1, s: 1, x: 195, y: 500 },
    { t: 89.0, s: 1, x: 195, y: 620 },
    { t: 89.7, s: 1.25, x: 195, y: 620 },
    { t: 92.6, s: 1.25, x: 195, y: 620 },
    { t: 93.4, s: 1, x: 195, y: 422 },
    { t: 101.6, s: 1, x: 195, y: 650 },
    { t: 102.2, s: 1.25, x: 195, y: 650 },
    { t: 103.3, s: 1.25, x: 195, y: 650 },
    { t: 103.9, s: 1, x: 195, y: 500 },
    { t: 106.8, s: 1, x: 195, y: 610 },
    { t: 107.5, s: 1.25, x: 195, y: 610 },
    { t: 109.6, s: 1.25, x: 195, y: 610 },
    { t: 110.3, s: 1, x: 195, y: 422 },
  ],

  highlights: [
    { t0: 51.3, t1: 53.4, rect: { x: 24, y: 136, w: 296, h: 100 }, label: 'Name & category', below: true },
    { t0: 53.6, t1: 55.5, rect: { x: 26, y: 284, w: 146, h: 40 }, label: 'Stock', below: false },
    { t0: 55.7, t1: 57.6, rect: { x: 28, y: 336, w: 334, h: 52 }, label: 'Tax', below: true },
    { t0: 58.6, t1: 60.6, rect: { x: 14, y: 484, w: 362, h: 82 }, label: 'Price', below: true },
    { t0: 102.0, t1: 103.4, rect: { x: 30, y: 674, w: 200, h: 30 }, label: 'Live preview', below: true },
    { t0: 110.6, t1: 112.8, target: 'details_open_scanner', pad: 6, label: 'Open Scanner', below: false },
    { t0: 113.6, t1: 115.8, target: 'home_logout', pad: 6, label: 'Log out', below: true },
  ],

  scans: [
    { t0: 21.6, t1: 24.6, rect: { x: 75, y: 279, w: 240, h: 240 }, flash: 24.6 },
    { t0: 39.2, t1: 42.6, rect: { x: 32, y: 313, w: 326, h: 190 }, flash: 42.6 },
  ],

  chapters: [
    { t0: 15.0, t1: 35.0, n: 1, title: 'Sign in' },
    { t0: 35.0, t1: 50.0, n: 2, title: 'Scan a product' },
    { t0: 50.0, t1: 63.0, n: 3, title: 'Product details' },
    { t0: 63.0, t1: 80.0, n: 4, title: 'Edit name & tax' },
    { t0: 80.0, t1: 94.0, n: 5, title: 'Update the price' },
    { t0: 94.0, t1: 110.0, n: 6, title: 'Update stock' },
    { t0: 110.0, t1: 116.4, n: 0, title: 'Keep going' },
  ],

  captions: [
    { t0: 15.6, t1: 19.2, text: 'Open the login QR code on your POS.' },
    { t0: 19.2, t1: 25.0, text: 'Tap <b>Tap to scan QR</b> and point the camera at it.' },
    { t0: 25.0, t1: 27.6, text: 'You are signed in securely.' },
    { t0: 27.6, t1: 34.8, text: 'Welcome to <b>Home</b>.' },
    { t0: 35.4, t1: 38.6, text: 'Tap the <b>scan button</b>.' },
    { t0: 38.6, t1: 43.0, text: 'Point at the barcode. It scans by itself.' },
    { t0: 43.0, t1: 49.8, text: 'The product opens right away.' },
    { t0: 50.4, t1: 53.5, text: 'Name and category.' },
    { t0: 53.5, t1: 55.6, text: 'Current stock.' },
    { t0: 55.6, t1: 58.4, text: 'Assigned tax.' },
    { t0: 58.4, t1: 60.8, text: 'Price in CHF.' },
    { t0: 60.8, t1: 62.8, text: 'Pencil icons open the editors.' },
    { t0: 63.4, t1: 65.8, text: 'Tap the <b>pencil</b> next to the name.' },
    { t0: 65.8, t1: 69.2, text: 'Type the new name.' },
    { t0: 69.2, t1: 72.4, text: 'Pick the tax.' },
    { t0: 72.4, t1: 75.6, text: '<b>Save Changes</b>, then <b>Confirm</b>.' },
    { t0: 75.6, t1: 79.8, text: 'Saved. The message shows what changed.' },
    { t0: 80.4, t1: 82.8, text: 'Tap the <b>pencil</b> next to Price.' },
    { t0: 82.8, t1: 85.2, text: 'Enter the new price.' },
    { t0: 85.2, t1: 88.4, text: 'Check it, then <b>Confirm</b>.' },
    { t0: 88.4, t1: 93.8, text: 'Price updated.' },
    { t0: 94.4, t1: 97.0, text: 'Tap the <b>pencil</b> next to the stock.' },
    { t0: 97.0, t1: 98.9, text: 'Choose <b>Update</b>, <b>Add</b> or <b>Remove</b>.' },
    { t0: 98.9, t1: 101.6, text: 'Enter the quantity.' },
    { t0: 101.6, t1: 103.6, text: 'Preview the new stock.' },
    { t0: 103.6, t1: 106.2, text: 'Confirm the change.' },
    { t0: 106.2, t1: 109.8, text: 'Stock updated.' },
    { t0: 110.4, t1: 113.0, text: 'Tap <b>Open Scanner</b> for the next product.' },
    { t0: 113.0, t1: 116.0, text: 'Log out from <b>Home</b> when you are done.' },
  ],

  // Shots with an orange bottom edge get a white home indicator.
  lightIndicator: ['login', 'home'],

  // Success toasts and sign-in get a chime.
  sfx: [
    { t: 27.5, kind: 'success' },
    { t: 75.9, kind: 'success' },
    { t: 88.7, kind: 'success' },
    { t: 106.5, kind: 'success' },
    { t: 51.3, kind: 'pop' },
    { t: 53.6, kind: 'pop' },
    { t: 55.7, kind: 'pop' },
    { t: 58.6, kind: 'pop' },
    { t: 102.0, kind: 'pop' },
    { t: 110.6, kind: 'pop' },
    { t: 113.6, kind: 'pop' },
    { t: 0.4, kind: 'riser' },
    { t: 116.5, kind: 'riser' },
  ],
};
