# Getting Started with OrangeOne — YouTube tutorial

A 2-minute, 16:9 Full HD tutorial for new users plus its thumbnail.
Scene plan: [STORYBOARD.md](STORYBOARD.md).

| Output | File |
|--------|------|
| Video (1920 × 1080, 30 fps, H.264 + AAC 48 kHz stereo, −14 LUFS) | `out/getting_started_with_orangeone.mp4` |
| Thumbnail (1280 × 720 PNG) | `out/getting_started_with_orangeone_thumbnail.png` |

Nothing here changes the app; `flutter test` in CI does not run this folder.

## Contents

| Path | What it is |
|------|------------|
| `capture/capture_tutorial_test.dart` | Drives the real app (Production environment, fictional in-memory products) and saves each screen state plus tap rectangles. Serves `brand/logo_mark.png` instead of the logo artwork, whose text is misspelled. Reuses the camera illustrations from `../onboarding_video/capture/camera_scenes.dart`. |
| `brand/` | Text-free crops of the supplied logo mark (125 px for the app capture, 500 px for titles and thumbnail). |
| `shots/` | Generated screenshots and `manifest.json` / `manifest.js`. |
| `animation/timeline.js` | **The editable script**: screens, taps, zooms, highlights, chapters, captions, extra sounds. |
| `animation/engine.js`, `animation/index.html` | Deterministic renderer and 16:9 layout. |
| `audio/make_audio.py` | Synthesizes the music and sound effects (numpy). |
| `thumbnail/thumbnail.html` | Thumbnail layout. |
| `render/render.mjs` | Frame capture (headless Chrome), audio, encoding (ffmpeg). |

## Regenerate

Prerequisites: Flutter, Node.js 18+, Python 3 with numpy (set `PYTHON` to
its executable if `python` on PATH lacks numpy), Google Chrome (or
`CHROME_PATH`).

```bash
flutter test --update-goldens marketing/youtube_tutorial/capture
```

```bash
cd marketing/youtube_tutorial/render && npm install
```

```bash
node render.mjs --thumbnail
```

```bash
node render.mjs
```

The full render takes about 15 minutes. While editing:
`animation/index.html?t=52` shows one frame in Chrome,
`node render.mjs --stills 20,52,102` writes PNG stills, and
`node render.mjs --from 60 --to 80` renders a silent clip.

## Audio and licensing

The music (a 96 BPM I–V–vi–IV piece with pad, plucked arpeggio, bass and
light drums) and all effects (tap, key clicks, whooshes, scan beep, chimes,
pops, risers) are generated from sine waves and noise by
`audio/make_audio.py`. No samples, loops or third-party recordings are used,
so the soundtrack is original work, free to use on YouTube. Sound cues come
from the timeline automatically (taps, push/pop transitions, typing, scans);
`sfx` in `timeline.js` adds chimes and pops. ffmpeg normalizes the mix to
−14 LUFS / −1.5 dBTP, YouTube's playback loudness.

## Common edits

- **Text**: `chapters` and `captions` in `timeline.js` (`<b>` marks UI labels).
- **Timing**: shift a section's `screens`, `taps`, `zooms`, `captions` and
  `sfx` together; keep taps ~0.2 s before the screen change they cause.
- **New screen state**: add `_shot`/`_tap` in the capture harness, recapture,
  then reference it in `timeline.js`.
- **Music**: change `BPM`, `CHORDS` or the levels in `make_audio.py`.
