"""Synthesizes the tutorial soundtrack: original background music plus
sound effects at the cues exported from the animation timeline.

Everything is generated here from sine waves and noise, so the audio is
original work with no third-party samples or licences involved.

Usage: python make_audio.py cues.json duration_seconds out.wav
"""

import json
import sys
import wave

import numpy as np

SR = 48000
RNG = np.random.default_rng(11)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def env(n, attack, release, sustain=None):
    """Attack/exponential-decay envelope of n samples."""
    a = max(1, int(attack * SR))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    if sustain is None:
        tail = np.arange(n - a) / SR
        e[a:] = np.exp(-tail / release)
    else:
        r = max(1, int(release * SR))
        e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff):
    """One-pole low-pass filter."""
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def note(freq):
    return 440.0 * 2 ** ((freq - 69) / 12)


def add(buf, start, sig):
    i = int(start * SR)
    if i >= len(buf):
        return
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


# --- Music -----------------------------------------------------------------

BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
# I - V - vi - IV in C major (MIDI notes), two bars each.
CHORDS = [
    (48, [60, 64, 67, 72]),
    (43, [59, 62, 67, 71]),
    (45, [57, 60, 64, 69]),
    (41, [57, 60, 65, 69]),
]


def pad_tone(freq, seconds):
    t = t_axis(seconds)
    sig = sum(
        np.sin(2 * np.pi * freq * d * t + p) / (k + 1)
        for k, (d, p) in enumerate([(1, 0), (1.003, 1.3), (0.997, 2.1), (2.001, 0.5)])
    )
    return sig * env(len(t), 0.9, 1.2, sustain=True)


def pluck(freq, seconds=0.9):
    t = t_axis(seconds)
    sig = (
        np.sin(2 * np.pi * freq * t)
        + 0.35 * np.sin(2 * np.pi * 2 * freq * t)
        + 0.12 * np.sin(2 * np.pi * 3 * freq * t)
    )
    return sig * env(len(t), 0.004, 0.28)


def kick():
    t = t_axis(0.35)
    freq = 45 + 70 * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * env(len(t), 0.002, 0.11)


def hat():
    n = int(0.06 * SR)
    noise = RNG.standard_normal(n)
    hp = noise - lowpass(noise, 6000)
    return hp * env(n, 0.001, 0.015)


def music(duration):
    out = np.zeros(int(duration * SR))
    pad = np.zeros_like(out)
    bars = int(duration / BAR) + 1
    hat_sound = hat()
    kick_sound = kick()
    for b in range(bars):
        start = b * BAR
        root, chord = CHORDS[(b // 2) % len(CHORDS)]
        if b % 2 == 0:
            for n_ in chord[:3]:
                add(pad, start, pad_tone(note(n_ - 12), 2 * BAR + 0.6) * 0.05)
        # Bass on beats 1 and 3.
        for beat in (0, 2):
            t = t_axis(BEAT * 1.6)
            bass = np.sin(2 * np.pi * note(root) * t) * env(len(t), 0.01, 0.45)
            add(out, start + beat * BEAT, bass * 0.16)
        # Gentle arpeggio in eighths, pattern varies per bar.
        pattern = [0, 2, 1, 3, 2, 1, 3, 2] if b % 2 else [0, 1, 2, 3, 2, 1, 2, 3]
        for k, idx in enumerate(pattern):
            add(out, start + k * BEAT / 2, pluck(note(chord[idx])) * 0.075)
        # Light rhythm after the intro.
        if start >= 7.0:
            for beat in (0, 2):
                add(out, start + beat * BEAT, kick_sound * 0.22)
            for k in range(8):
                add(out, start + k * BEAT / 2 + 0.01, hat_sound * (0.05 if k % 2 else 0.03))
    out += lowpass(pad, 1800)
    # Fade in and out.
    fade_in = int(2.0 * SR)
    fade_out = int(4.0 * SR)
    out[:fade_in] *= np.linspace(0, 1, fade_in)
    out[-fade_out:] *= np.linspace(1, 0, fade_out) ** 1.5
    return out


# --- Sound effects --------------------------------------------------------


def sfx_tap():
    t = t_axis(0.06)
    click = np.sin(2 * np.pi * 1700 * t) * env(len(t), 0.001, 0.012)
    tick = RNG.standard_normal(len(t)) * env(len(t), 0.0005, 0.004)
    return (click * 0.5 + tick * 0.15) * 0.9


def sfx_key():
    t = t_axis(0.04)
    return (
        RNG.standard_normal(len(t)) * env(len(t), 0.0005, 0.006) * 0.12
        + np.sin(2 * np.pi * 2400 * t) * env(len(t), 0.0005, 0.005) * 0.15
    )


def sfx_whoosh(seconds=0.45, low=300, high=2600):
    n = int(seconds * SR)
    noise = RNG.standard_normal(n)
    # Sweep the cut-off upward, shaped by a smooth bell envelope.
    out = np.empty(n)
    acc = 0.0
    for i in range(n):
        cut = low + (high - low) * (i / n)
        alpha = 1 - np.exp(-2 * np.pi * cut / SR)
        acc += alpha * (noise[i] - acc)
        out[i] = acc
    bell = np.sin(np.pi * np.arange(n) / n) ** 2
    return out * bell * 0.35


def sfx_chime():
    out = np.zeros(int(1.2 * SR))
    for k, m in enumerate([84, 88, 91]):  # C6 E6 G6
        t = t_axis(0.9)
        f = note(m)
        tone = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2.76 * f * t)) * env(len(t), 0.003, 0.32)
        add(out, k * 0.085, tone * 0.16)
    return out


def sfx_scan():
    out = np.zeros(int(0.3 * SR))
    for k, f in enumerate([1320, 1760]):
        t = t_axis(0.09)
        add(out, k * 0.1, np.sin(2 * np.pi * f * t) * env(len(t), 0.003, 0.05) * 0.2)
    return out


def sfx_pop():
    t = t_axis(0.12)
    freq = 520 + 380 * np.exp(-t / 0.02)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(len(t), 0.002, 0.035) * 0.22


def sfx_riser():
    t = t_axis(1.6)
    sig = sum(np.sin(2 * np.pi * note(m) * t) for m in (60, 67, 72, 76)) / 4
    shimmer = lowpass(RNG.standard_normal(len(t)), 3000) * 0.3
    e = np.minimum(1, t / 0.9) * np.exp(-np.maximum(0, t - 0.9) / 0.35)
    return (sig + shimmer) * e * 0.18


SFX = {
    'tap': sfx_tap(),
    'key': sfx_key(),
    'whoosh': sfx_whoosh(),
    'swish': sfx_whoosh(0.6, 200, 1400) * 0.6,
    'success': sfx_chime(),
    'scan': sfx_scan(),
    'pop': sfx_pop(),
    'riser': sfx_riser(),
}


def main():
    cues_path, duration, out_path = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    with open(cues_path, encoding='utf-8') as f:
        cues = json.load(f)
    bed = music(duration) * 0.85
    fx = np.zeros_like(bed)
    for cue in cues:
        add(fx, max(0.0, cue['t']), SFX[cue['kind']])
    mix = bed + fx * 1.1
    # Gentle soft-clip, then normalize to -1 dBFS peak (loudness is set by
    # ffmpeg's loudnorm at mux time).
    mix = np.tanh(mix * 1.2) / np.tanh(1.2)
    mix *= 10 ** (-1 / 20) / max(1e-9, np.max(np.abs(mix)))
    # Slight stereo width: delay the right channel by 7 ms on the music bed.
    right = mix.copy()
    d = int(0.007 * SR)
    right[d:] = 0.8 * mix[d:] + 0.2 * mix[:-d]
    stereo = np.stack([mix, right], axis=1)
    pcm = (np.clip(stereo, -1, 1) * 32767).astype('<i2')
    with wave.open(out_path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(out_path)


if __name__ == '__main__':
    main()
