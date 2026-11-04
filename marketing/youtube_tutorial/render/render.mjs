// Renders the tutorial video and thumbnail.
//
//   node render.mjs                     video  -> ../out/getting_started_with_orangeone.mp4
//   node render.mjs --thumbnail         image  -> ../out/getting_started_with_orangeone_thumbnail.png
//   node render.mjs --stills 8,25.5,61  PNG stills -> ../out/stills/
//   node render.mjs --from 30 --to 45   silent partial clip for review
//
// Video frames come from animation/index.html (headless Chrome); the sound
// cues are read from the page, audio/make_audio.py synthesizes the music
// and effects, and ffmpeg encodes H.264 + AAC with YouTube loudness.
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import ffmpegPath from 'ffmpeg-static';
import puppeteer from 'puppeteer-core';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const out = join(root, 'out');
const args = process.argv.slice(2);
const arg = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const name = 'getting_started_with_orangeone';

const chrome =
  process.env.CHROME_PATH ||
  [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ].find(existsSync);
if (!chrome) throw new Error('Chrome not found; set CHROME_PATH.');
const python = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');

mkdirSync(out, { recursive: true });
const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  args: ['--hide-scrollbars', '--force-color-profile=srgb', '--disable-lcd-text'],
});
const page = await browser.newPage();

if (args.includes('--thumbnail')) {
  await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(join(root, 'thumbnail', 'thumbnail.html')).href, { waitUntil: 'load' });
  await page.evaluate(() => window.ready);
  const file = join(out, `${name}_thumbnail.png`);
  await page.screenshot({ path: file, type: 'png' });
  await browser.close();
  console.log(file);
  process.exit(0);
}

await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(join(root, 'animation', 'index.html')).href + '?render=1', { waitUntil: 'load' });
await page.evaluate(() => window.ready);
const { duration, fps, cues } = await page.evaluate(() => ({
  duration: window.TIMELINE.duration,
  fps: window.TIMELINE.fps,
  cues: window.soundCues(),
}));

const frame = async (t) => {
  await page.evaluate((time) => window.renderAt(time), t);
  return page.screenshot({ type: 'png', optimizeForSpeed: true });
};

const stills = arg('--stills');
if (stills) {
  mkdirSync(join(out, 'stills'), { recursive: true });
  for (const t of stills.split(',').map(Number)) {
    const file = join(out, 'stills', `t${t.toFixed(2).padStart(6, '0')}.png`);
    writeFileSync(file, await frame(t));
    console.log(file);
  }
  await browser.close();
  process.exit(0);
}

const from = Number(arg('--from') ?? 0);
const to = Number(arg('--to') ?? duration);
const partial = from > 0 || to < duration;

// Audio for the full video only.
const audio = join(out, 'soundtrack.wav');
if (!partial) {
  const cueFile = join(out, 'cues.json');
  writeFileSync(cueFile, JSON.stringify(cues, null, 1));
  const made = spawnSync(python, [join(root, 'audio', 'make_audio.py'), cueFile, String(duration), audio], { stdio: 'inherit' });
  if (made.status !== 0) throw new Error('Audio synthesis failed (needs Python 3 with numpy; set PYTHON).');
}

const target = join(out, partial ? `clip_${from}-${to}.mp4` : `${name}.mp4`);
// An MP4 has no index until ffmpeg finishes, so it is unplayable while it is
// written. Encode under a temporary name and rename it only when complete.
const working = target.replace(/\.mp4$/, '.rendering.mp4');
rmSync(target, { force: true });
const ffmpeg = spawn(
  ffmpegPath,
  [
    '-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    ...(partial ? [] : ['-i', audio]),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17',
    '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.2', '-g', String(fps / 2),
    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
    ...(partial ? [] : ['-c:a', 'aac', '-b:a', '320k', '-af', 'loudnorm=I=-14:TP=-1.5:LRA=11', '-ar', '48000', '-shortest']),
    '-movflags', '+faststart',
    working,
  ],
  { stdio: ['pipe', 'inherit', 'inherit'] },
);
const finished = new Promise((ok, fail) =>
  ffmpeg.on('close', (code) => (code === 0 ? ok() : fail(new Error(`ffmpeg exited ${code}`)))),
);

const total = Math.round((to - from) * fps);
const started = Date.now();
for (let i = 0; i < total; i++) {
  const png = await frame(from + i / fps);
  if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once('drain', r));
  if (i % (fps * 5) === 0) {
    const eta = ((Date.now() - started) / (i + 1)) * (total - i) / 1000;
    console.log(`frame ${i}/${total}  ~${eta.toFixed(0)}s left`);
  }
}
ffmpeg.stdin.end();
await finished;
await browser.close();
renameSync(working, target);
console.log(target);
