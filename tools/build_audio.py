#!/usr/bin/env python3
"""Cuts the district ambience and grill loop the game ships from the CC0 sources
in raw/audio-candidates/ (git-ignored; the source pages are listed in README.md).

    python3 -I tools/build_audio.py            # writes assets/sfx/ambience, assets/sfx/loops
    python3 -I tools/build_audio.py --check    # prints what it would write

Needs numpy and soundfile (libsndfile 1.1+ for MP3). Ambience and loops are cut to the
steadiest stretch of the recording and closed with an equal-power crossfade, so they
repeat without a click. The owner asked for a light soundscape with no music (2026-11-12):
the music candidates stay in raw/ and a "music" / "music-ends" job would be kept whole. Run `Godot --headless --path . --import` after.
"""
import io
import os
import struct
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "raw", "audio-candidates")

# kind, source, output, target RMS dB, Vorbis quality, loop seconds (0 = whole file), crossfade seconds
JOBS = [
    ("whole", "amb-street/amb_outdoor1_loop.ogg", "assets/sfx/ambience/street.ogg", -30.0, 0.2, 0, 0),
    ("bed", "amb-metro/gatve_Varniu_2.ogg", "assets/sfx/ambience/metro.ogg", -30.0, 0.2, 30, 3),
    ("bed", "amb-beach/on_a_pebble_beach.ogg", "assets/sfx/ambience/jbr.ogg", -30.0, 0.2, 30, 3),
    ("bed", "amb-downtown/sunday_in_the_city.ogg", "assets/sfx/ambience/downtown.ogg", -30.0, 0.2, 30, 3),
    ("bed", "amb-mall/alexa_mall_berlin.ogg", "assets/sfx/ambience/mall.ogg", -30.0, 0.2, 30, 3),
    ("bed", "amb-evening/restaurant_ambience.ogg", "assets/sfx/ambience/gv.ogg", -30.0, 0.2, 30, 3),
    ("bed", "loop-sizzle/frying_fries.ogg", "assets/sfx/loops/grill_sizzle.ogg", -33.0, 0.2, 8, 1),
]
PEAK = 0.89


def vorbis_only(data: bytes) -> bytes:
    """Wikimedia's Ogg files carry a Skeleton stream libsndfile rejects: keep the Vorbis pages."""
    pages, pos, keep = [], 0, None
    while pos + 27 <= len(data) and data[pos:pos + 4] == b"OggS":
        serial = struct.unpack_from("<I", data, pos + 14)[0]
        nseg = data[pos + 26]
        size = 27 + nseg + sum(data[pos + 27:pos + 27 + nseg])
        body = data[pos + 27 + nseg:pos + size]
        if keep is None and body.startswith(b"\x01vorbis"):
            keep = serial
        pages.append((serial, data[pos:pos + size]))
        pos += size
    if keep is None:
        raise ValueError("no Vorbis stream")
    return b"".join(page for serial, page in pages if serial == keep)


def read(path: str):
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"OggS"):
        raw = vorbis_only(raw)
    return sf.read(io.BytesIO(raw), dtype="float32", always_2d=True)


def rms_db(x) -> float:
    return 20.0 * np.log10(float(np.sqrt(np.mean(np.square(x)))) + 1e-9)


def steadiest(mono, sr: int, length: int) -> int:
    """Start of the window whose half-second loudness varies least (no passing car, no shout)."""
    hop = sr // 2
    levels = np.array([rms_db(mono[i:i + hop]) for i in range(0, len(mono) - hop, hop)])
    span = length // hop
    best, best_score = 0, 1e9
    for i in range(1, max(2, len(levels) - span)):
        w = levels[i:i + span]
        score = float(w.max() - w.min()) + float(w.std())
        if score < best_score:
            best, best_score = i, score
    return best * hop


def loop_cut(x, sr: int, seconds: float, fade: float):
    n, f = int(seconds * sr), int(fade * sr)
    if len(x) < n + f + sr:
        n = len(x) - f - sr
    start = steadiest(x.mean(axis=1), sr, n + f)
    start = min(start, len(x) - n - f)
    body = x[start:start + n].copy()
    t = np.linspace(0.0, np.pi / 2.0, f, dtype=np.float32)[:, None]
    body[:f] = body[:f] * np.sin(t) + x[start + n:start + n + f] * np.cos(t)
    return body, start / sr


def trim_silence(x, sr: int, floor: float = 0.003, tail: float = 0.6):
    loud = np.flatnonzero(np.abs(x).max(axis=1) > floor)
    a, b = int(loud[0]), min(len(x), int(loud[-1]) + int(tail * sr))
    y = x[a:b].copy()
    f = int(0.02 * sr)
    y[:f] *= np.linspace(0.0, 1.0, f, dtype=np.float32)[:, None]
    y[-f:] *= np.linspace(1.0, 0.0, f, dtype=np.float32)[:, None]
    return y


def level(x, target_db: float):
    gain = 10.0 ** ((target_db - rms_db(x)) / 20.0)
    peak = float(np.abs(x).max()) * gain
    if peak > PEAK:
        gain *= PEAK / peak
    return x * gain


def write(path: str, x, sr: int, quality: float) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with sf.SoundFile(path, "w", samplerate=sr, channels=x.shape[1], format="OGG",
            subtype="VORBIS", compression_level=1.0 - quality) as out:
        for i in range(0, len(x), sr * 5):  # libsndfile overflows on one very long Vorbis write
            out.write(x[i:i + sr * 5])


def main() -> int:
    check = "--check" in sys.argv
    total = 0
    for kind, src, dst, target, quality, seconds, fade in JOBS:
        x, sr = read(os.path.join(SRC, src))
        note = "whole"
        if kind in ("bed", "whole"):
            x = x.mean(axis=1, keepdims=True)
        if kind == "bed":
            x, at = loop_cut(x, sr, seconds, fade)
            note = "from %.1fs" % at
        elif kind == "music-ends":
            x = trim_silence(x, sr)
            note = "silence trimmed"
        x = level(x, target)
        out = os.path.join(ROOT, dst)
        if not check:
            write(out, x, sr, quality)
        size = os.path.getsize(out) if os.path.exists(out) else 0
        total += size
        seam = float(np.abs(x[0] - x[-1]).max())
        print("%-36s %6.1fs ch%d %6.1f dB peak %.2f seam %.3f %7.1f KB  %s" % (
            dst, len(x) / sr, x.shape[1], rms_db(x), float(np.abs(x).max()), seam, size / 1024.0, note))
    print("total %.2f MB" % (total / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
