// Deterministic renderer: window.renderAt(t) sets every element for time t,
// so any frame can be produced in any order. Only transform and opacity are
// animated; easing curves follow the animate skill. window.soundCues() lists
// the sound effects implied by the timeline for audio/make_audio.py.
(() => {
  const T = window.TIMELINE;
  const M = window.MANIFEST;
  const SCREEN_W = 444;
  const K = SCREEN_W / M.viewport.width; // logical px -> screen px
  const PHONE = { x: 1124 + 14, y: 45 + 14 }; // screen origin on the stage
  const $ = (id) => document.getElementById(id);

  // --- Easing ---------------------------------------------------------------
  function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
    const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    const sx = (u) => ((ax * u + bx) * u + cx) * u;
    const sy = (u) => ((ay * u + by) * u + cy) * u;
    const dx = (u) => (3 * ax * u + 2 * bx) * u + cx;
    return (x) => {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      let u = x;
      for (let i = 0; i < 8; i++) {
        const err = sx(u) - x;
        if (Math.abs(err) < 1e-6) break;
        const d = dx(u);
        if (Math.abs(d) < 1e-6) break;
        u -= err / d;
      }
      return sy(Math.min(1, Math.max(0, u)));
    };
  }
  const E = {
    outQuint: bezier(0.23, 1, 0.32, 1),
    inOutCubic: bezier(0.645, 0.045, 0.355, 1),
    outCubic: bezier(0.33, 1, 0.68, 1),
    inCubic: bezier(0.32, 0, 0.67, 0),
    outBack: bezier(0.34, 1.56, 0.64, 1),
    linear: (x) => x,
  };
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const prog = (t, t0, dur, ease = E.linear) => ease(clamp((t - t0) / dur));
  const lerp = (a, b, p) => a + (b - a) * p;
  // In over din from t0, out over dout ending at t1 (exits ~75% of enters).
  const span = (t, t0, t1, din = 0.45, dout = 0.32) =>
    Math.min(prog(t, t0, din, E.outQuint), 1 - prog(t, t1 - dout, dout, E.inCubic));
  const css = (el, props) => {
    for (const [k, v] of Object.entries(props)) el.style[k] = v;
  };

  // --- Construction ---------------------------------------------------------
  const shotUrl = (name) => `../shots/${name}.png`;
  const pool = document.createElement('div');
  pool.style.cssText = 'position:absolute;left:-9999px;top:0;width:1px;height:1px;overflow:hidden';
  document.body.appendChild(pool);
  const pooled = [...new Set(T.screens.map((s) => s.shot))].map((name) => {
    const img = new Image();
    img.src = shotUrl(name);
    pool.appendChild(img);
    return img;
  });
  const slots = [0, 1, 2].map(() => {
    const div = document.createElement('div');
    div.className = 'slot';
    const img = document.createElement('img');
    div.appendChild(img);
    $('slots').appendChild(div);
    return { div, img, shot: null };
  });
  const make = (cls, parent = $('fx')) => {
    const el = document.createElement('div');
    el.className = cls;
    parent.appendChild(el);
    return el;
  };
  const finger = make('finger');
  const ripple = make('ripple');
  const hl = make('hl');
  const hlLabel = make('hl-label', hl);
  const scanline = make('scanline');
  const flash = make('flash');

  const spell = (el, text) =>
    text.split('').map((ch) => {
      const span_ = document.createElement('span');
      span_.textContent = ch;
      el.appendChild(span_);
      return span_;
    });
  const introLetters = spell($('introTitle'), 'Getting Started with OrangeOne');
  const numbered = T.chapters.filter((c) => c.n > 0);
  numbered.forEach(() => make('seg', $('progress')).appendChild(document.createElement('i')));
  const segs = [...$('progress').children].map((s) => s.firstChild);

  const rectOf = (target) => (typeof target === 'string' ? M.targets[target] : target);

  // --- Screen layers ----------------------------------------------------------
  const DUR = { push: 0.5, pop: 0.45, fade: 0.45, modal: 0.24, cut: 0, scroll: 0.6 };

  function screenLayers(t) {
    let i = 0;
    while (i + 1 < T.screens.length && T.screens[i + 1].t <= t) i++;
    const cur = T.screens[i];
    const prev = T.screens[i - 1];
    const dur = DUR[cur.tr] ?? 0;
    const p = dur ? clamp((t - cur.t) / dur) : 1;
    const full = (shot, o = {}) => ({ shot, top: 0, bottom: M.viewport.height, tx: 0, ty: 0, opacity: 1, dim: 0, ...o });
    if (!prev || p >= 1) return { shot: cur.shot, layers: [full(cur.shot)] };
    const e = E.inOutCubic(p);
    switch (cur.tr) {
      case 'push':
        return { shot: cur.shot, layers: [full(prev.shot, { tx: -0.28 * e, dim: 0.25 * e }), full(cur.shot, { tx: 1 - e, shadow: true })] };
      case 'pop':
        return { shot: cur.shot, layers: [full(cur.shot, { tx: -0.28 * (1 - e), dim: 0.25 * (1 - e) }), full(prev.shot, { tx: e, shadow: true })] };
      case 'scroll': {
        const { d, top, bottom } = cur.scroll;
        return {
          shot: cur.shot,
          layers: [
            full(cur.shot),
            full(prev.shot, { top, bottom, ty: -d * e }),
            full(cur.shot, { top: top + d * (1 - e), bottom, ty: d * (1 - e) }),
          ],
        };
      }
      default: {
        const o = cur.tr === 'modal' ? E.outCubic(p) : p;
        return { shot: cur.shot, layers: [full(prev.shot), full(cur.shot, { opacity: o })] };
      }
    }
  }

  function drawScreen(t) {
    const { shot, layers } = screenLayers(t);
    const pending = [];
    slots.forEach((slot, i) => {
      const l = layers[i];
      if (!l) {
        slot.div.style.display = 'none';
        return;
      }
      slot.div.style.display = 'block';
      if (slot.shot !== l.shot) {
        slot.shot = l.shot;
        slot.img.src = shotUrl(l.shot);
        pending.push(slot.img.decode().catch(() => {}));
      }
      css(slot.div, {
        top: `${l.top * K}px`,
        height: `${(l.bottom - l.top) * K}px`,
        transform: `translateX(${l.tx * SCREEN_W}px)`,
        opacity: l.opacity,
        filter: l.dim ? `brightness(${1 - l.dim})` : 'none',
        boxShadow: l.shadow ? '-18px 0 36px rgba(0,0,0,.25)' : 'none',
        zIndex: i,
      });
      css(slot.img, { top: `${(-l.top + l.ty) * K}px` });
    });
    $('homeInd').style.background = T.lightIndicator.includes(shot) ? 'rgba(255,255,255,.9)' : 'rgba(20,20,20,.85)';
    return pending;
  }

  // --- Overlays -----------------------------------------------------------------
  function drawTouch(t) {
    let shown = false;
    for (const tap of T.taps) {
      if (t < tap.t - 0.6 || t > tap.t + 0.5) continue;
      const r = rectOf(tap.target);
      const x = (r.x + r.w / 2) * K;
      const y = (r.y + r.h / 2) * K;
      const appear = prog(t, tap.t - 0.6, 0.35, E.outQuint);
      const leave = prog(t, tap.t + 0.22, 0.25, E.inCubic);
      const press = t < tap.t ? prog(t, tap.t - 0.12, 0.12, E.outCubic) : 1 - prog(t, tap.t, 0.16, E.outCubic);
      css(finger, {
        display: 'block', left: `${x + lerp(40, 0, appear)}px`, top: `${y + lerp(60, 0, appear)}px`,
        opacity: appear * (1 - leave), transform: `scale(${lerp(1.25, 1, appear) * (1 - 0.18 * press)})`,
      });
      const rp = prog(t, tap.t, 0.55, E.outQuint);
      css(ripple, {
        display: t >= tap.t ? 'block' : 'none', left: `${x}px`, top: `${y}px`,
        opacity: 0.85 * (1 - rp), transform: `scale(${lerp(0.8, 2.8, rp)})`,
      });
      shown = true;
      break;
    }
    for (const sw of T.swipes) {
      if (shown || t < sw.t0 - 0.35 || t > sw.t1 + 0.3) continue;
      const appear = prog(t, sw.t0 - 0.35, 0.3, E.outQuint);
      const leave = prog(t, sw.t1, 0.3, E.inCubic);
      const m = prog(t, sw.t0, sw.t1 - sw.t0, E.inOutCubic);
      css(finger, {
        display: 'block', left: `${lerp(sw.from.x, sw.to.x, m) * K}px`, top: `${lerp(sw.from.y, sw.to.y, m) * K}px`,
        opacity: appear * (1 - leave), transform: 'scale(.9)',
      });
      ripple.style.display = 'none';
      shown = true;
    }
    if (!shown) {
      finger.style.display = 'none';
      ripple.style.display = 'none';
    }
  }

  function drawHighlight(t) {
    const h = T.highlights.find((x) => t >= x.t0 && t <= x.t1);
    if (!h) {
      hl.style.display = 'none';
      return;
    }
    const a = span(t, h.t0, h.t1, 0.35, 0.25);
    const base = h.rect || rectOf(h.target);
    const pad = h.pad || 0;
    const r = { x: base.x - pad, y: base.y - pad, w: base.w + 2 * pad, h: base.h + 2 * pad };
    css(hl, {
      display: 'block', left: `${r.x * K}px`, top: `${r.y * K}px`, width: `${r.w * K}px`, height: `${r.h * K}px`,
      opacity: a, transform: `scale(${lerp(1.06, 1, a)})`,
    });
    hlLabel.textContent = h.label;
    // Keep the label inside the screen.
    const right = r.x * K + 20 + h.label.length * 12 > SCREEN_W;
    css(hlLabel, {
      left: right ? 'auto' : '0', right: right ? '0' : 'auto',
      top: h.below ? `${r.h * K + 12}px` : 'auto', bottom: h.below ? 'auto' : `${r.h * K + 12}px`,
    });
  }

  function drawScan(t) {
    const s = T.scans.find((x) => t >= x.t0 - 0.2 && t <= x.flash + 0.6);
    if (!s) {
      scanline.style.display = 'none';
      flash.style.display = 'none';
      return;
    }
    const r = s.rect;
    const phase = clamp((t - s.t0) / (s.t1 - s.t0)) * 2;
    const y = phase < 1 ? E.inOutCubic(phase) : 1 - E.inOutCubic(phase - 1);
    css(scanline, {
      display: 'block', left: `${(r.x + 14) * K}px`, width: `${(r.w - 28) * K}px`,
      top: `${(r.y + 12 + y * (r.h - 24)) * K}px`, opacity: span(t, s.t0 - 0.2, s.t1, 0.25, 0.2),
    });
    const f = t >= s.flash ? 1 - prog(t, s.flash, 0.6, E.outCubic) : 0;
    css(flash, {
      display: f > 0 ? 'block' : 'none', left: `${(r.x - 6) * K}px`, top: `${(r.y - 6) * K}px`,
      width: `${(r.w + 12) * K}px`, height: `${(r.h + 12) * K}px`, opacity: f, transform: `scale(${lerp(1.08, 1, f)})`,
    });
  }

  // Camera: scale around a logical focus point, then pull it toward the
  // phone's resting centre so zoomed details stay inside the frame.
  function drawCamera(t) {
    const z = T.zooms;
    let i = 0;
    while (i + 1 < z.length && z[i + 1].t <= t) i++;
    const a = z[i];
    const b = z[i + 1] || a;
    const p = b === a ? 0 : E.inOutCubic(clamp((t - a.t) / (b.t - a.t)));
    const s = lerp(a.s, b.s, p);
    const px = PHONE.x + lerp(a.x, b.x, p) * K;
    const py = PHONE.y + lerp(a.y, b.y, p) * K;
    const enter = prog(t, T.phoneIn, 1.0, E.outQuint);
    const exit = prog(t, T.phoneOut, 0.7, E.inCubic);
    const dx = lerp(900, 0, enter) + lerp(0, 900, exit);
    // Keep the focus point within the vertical frame at high zoom.
    const pull = (s - 1) * (540 - py) * 0.9;
    $('camera').style.transform = `translate(${px * (1 - s) + dx}px, ${py * (1 - s) + pull}px) scale(${s})`;
    $('camera').style.opacity = t < T.phoneIn ? 0 : 1 - prog(t, T.phoneOut + 0.35, 0.35);
  }

  function drawPanel(t) {
    const first = T.chapters[0].t0;
    const last = T.chapters[T.chapters.length - 1].t1;
    const panelA = span(t, first, last, 0.6, 0.4);
    $('panel').style.opacity = panelA > 0 ? 1 : 0;
    const brand = span(t, first, last, 0.6, 0.4);
    css($('brandRow'), { opacity: brand, transform: `translateY(${lerp(-20, 0, brand)}px)` });
    $('progress').style.opacity = brand;
    numbered.forEach((c, i) => {
      segs[i].style.width = `${clamp((t - c.t0) / (c.t1 - c.t0)) * 100}%`;
    });

    const ch = T.chapters.find((c) => t >= c.t0 && t < c.t1);
    if (!ch) {
      $('chapterNo').style.opacity = 0;
      $('chapterTitle').style.opacity = 0;
    } else {
      $('chapterNo').textContent = ch.n ? `CHAPTER ${ch.n}` : 'TIPS';
      $('chapterTitle').textContent = ch.title;
      const no = span(t, ch.t0 + 0.05, ch.t1, 0.5, 0.3);
      const ti = span(t, ch.t0 + 0.15, ch.t1, 0.55, 0.3);
      css($('chapterNo'), { opacity: no, transform: `translateX(${lerp(-40, 0, no)}px)` });
      css($('chapterTitle'), { opacity: ti, transform: `translateX(${lerp(-60, 0, ti)}px)` });
    }
    const cap = T.captions.find((c) => t >= c.t0 && t < c.t1);
    const el = $('caption');
    if (!cap) {
      el.style.opacity = 0;
      return;
    }
    if (el.dataset.key !== String(cap.t0)) {
      el.dataset.key = String(cap.t0);
      el.innerHTML = cap.text;
    }
    const a = span(t, cap.t0, cap.t1, 0.4, 0.25);
    css(el, { opacity: a, transform: `translateY(${lerp(20, 0, a)}px)` });
  }

  function drawBackground(t) {
    [['orb1', -300, -300, 0], ['orb2', 1300, 500, 2], ['orb3', 700, 700, 4]].forEach(([id, x, y, ph]) => {
      const dx = Math.sin(t * 0.13 + ph) * 70;
      const dy = Math.cos(t * 0.1 + ph) * 50;
      $(id).style.transform = `translate(${x + dx}px, ${y + dy}px)`;
    });
  }

  function drawCards(t) {
    // Intro (0-7 s).
    const out = prog(t, 6.2, 0.5, E.inCubic);
    $('intro').style.display = t > 6.8 ? 'none' : 'block';
    const logo = prog(t, 0.4, 0.8, E.outBack);
    css($('introLogo'), {
      opacity: clamp(logo * 1.5) * (1 - out),
      transform: `translateY(${-80 * out}px) scale(${lerp(0.5, 1, logo)}) rotate(${lerp(-8, 0, logo)}deg)`,
    });
    introLetters.forEach((el, i) => {
      const a = prog(t, 1.0 + i * 0.028, 0.55, E.outQuint);
      css(el, { opacity: a * (1 - out), transform: `translateY(${lerp(50, 0, a) - 80 * out}px)` });
    });
    const sub = prog(t, 2.2, 0.6, E.outQuint);
    css($('introSub'), { opacity: sub * (1 - out), transform: `translateY(${lerp(30, 0, sub) - 80 * out}px)` });

    // Before you start (7-14.4 s).
    $('need').style.display = t < 6.9 || t > 14.4 ? 'none' : 'block';
    const nOut = prog(t, 13.7, 0.5, E.inCubic);
    const nt = prog(t, 7.1, 0.6, E.outQuint);
    css($('needTitle'), { opacity: nt * (1 - nOut), transform: `translateY(${lerp(30, 0, nt) - 60 * nOut}px)` });
    [['need1', 7.7], ['need2', 8.4]].forEach(([id, t0]) => {
      const a = prog(t, t0, 0.6, E.outBack);
      css($(id), { opacity: clamp(a) * (1 - nOut), transform: `translateY(${lerp(80, 0, a) - 60 * nOut}px) scale(${lerp(0.9, 1, clamp(a))})` });
    });

    // Outro.
    const t0 = T.phoneOut + 0.6;
    $('outro').style.display = t < t0 ? 'none' : 'block';
    const end = prog(t, T.duration - 0.8, 0.8, E.inCubic);
    const ol = prog(t, t0, 0.8, E.outBack);
    css($('outroLogo'), { opacity: clamp(ol * 1.5) * (1 - end), transform: `scale(${lerp(0.5, 1, ol)})` });
    const ot = prog(t, t0 + 0.4, 0.6, E.outQuint);
    css($('outroTitle'), { opacity: ot * (1 - end), transform: `translateY(${lerp(40, 0, ot)}px)` });
    const os = prog(t, t0 + 0.9, 0.6, E.outQuint);
    css($('outroSub'), { opacity: os * (1 - end), transform: `translateY(${lerp(30, 0, os)}px)` });
  }

  window.renderAt = async (t) => {
    drawBackground(t);
    drawCards(t);
    drawCamera(t);
    const pending = drawScreen(t);
    drawTouch(t);
    drawHighlight(t);
    drawScan(t);
    drawPanel(t);
    await Promise.all(pending);
  };

  // Sound cues implied by the timeline (seconds, kind).
  window.soundCues = () => {
    const cues = [];
    T.taps.forEach((tap) => cues.push({ t: tap.t, kind: 'tap' }));
    T.screens.forEach((s, i) => {
      if (i === 0) return;
      if (s.tr === 'push' || s.tr === 'pop') cues.push({ t: s.t, kind: 'whoosh' });
      if (s.tr === 'scroll') cues.push({ t: s.t, kind: 'swish' });
      // Typing: key clicks just before each typed state appears.
      if (/_type_\d+$/.test(s.shot)) {
        for (let k = 0; k < 3; k++) cues.push({ t: s.t - 0.36 + k * 0.11, kind: 'key' });
      }
    });
    T.scans.forEach((s) => cues.push({ t: s.flash, kind: 'scan' }));
    cues.push({ t: T.phoneIn, kind: 'whoosh' }, { t: T.phoneOut, kind: 'whoosh' });
    return [...cues, ...T.sfx].sort((a, b) => a.t - b.t);
  };

  window.ready = (async () => {
    await document.fonts.load('700 40px Inter');
    await document.fonts.ready;
    await Promise.all([...pooled, ...document.querySelectorAll('img')].map((img) => img.decode().catch(() => {})));
    await window.renderAt(0);
    return true;
  })();

  // Preview: ?t=12.5 shows a still, otherwise it plays in real time.
  const params = new URLSearchParams(location.search);
  if (!params.has('render')) {
    window.ready.then(() => {
      if (params.has('t')) return window.renderAt(Number(params.get('t')));
      const start = performance.now();
      const tick = () => {
        window.renderAt(((performance.now() - start) / 1000) % T.duration);
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
  }
})();
