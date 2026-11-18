#!/usr/bin/env python3
"""Builds the district ambience and the grill loop the game ships from the CC0 and
public-domain sources in raw/audio-candidates/ (git-ignored; the source pages are listed
in README.md).

    python3 -I tools/build_audio.py            # writes assets/sfx/ambience, assets/sfx/loops
    python3 -I tools/build_audio.py --check    # prints what it would write

Needs numpy and soundfile (libsndfile 1.1+ for MP3). Run `Godot --headless --path . --import`
afterwards.

The owner asked for a light soundscape with no music (2026-11-12), and then said the first
beds sounded "as if I am in the toilet" (2026-11-18): they were steady broadband noise
(running-water hiss, low rumble). A bed here is therefore a MIX OF EVENTS over near
silence, never a noise bed:
  - every layer is band-limited to what carries its character (no rumble, no hiss);
  - an expander pushes down whatever lies between the events of a layer;
  - a layer of people is kept far below the events, as a hint that the place is alive;
  - the report line of each bed states its floor, its events and how much of it is
    rumble or hiss, and the build FAILS when a bed is steady noise again.
"""
import io
import os
import struct
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "raw", "audio-candidates")
RATE = 44100
SECONDS = 30.0
PEAK = 0.89

BIRDS = "r4-birds-oga/birds-isaiah658.ogg"          # clean sparse chirps, near-silent floor
GARDEN = "r4-birds-garden/Birds_singing_in_garden.ogg"
SUNNY = "r4-birds-sunny/Birdsong_mild_sunny_day.ogg"
PEOPLE = "amb-evening/restaurant_ambience.ogg"       # a room of quiet talk
MALL = "amb-mall/alexa_mall_berlin.ogg"
WAVES = "r4-waves-lake/Waves.ogg"
GULL_A = "r4-gull-1/Gull_1.ogg"
GULL_B = "r4-gull-2/Gull_2.ogg"
CRICKETS = "r4-crickets/crickets-oneloop.mp3"
FIRE = "r4-fire-short/fire-1.ogg"
EMBERS = "r4-fire-loop/fire.wav"

# A layer: source, band (Hz), level of its events (dB, 95th percentile of 50 ms loudness),
# expander depth (dB taken off between events; 0 = leave as recorded), and how it is laid
# into the loop: "loop" = a looped stretch from `at` seconds, "calls" = the clip dropped at
# the given times (seconds), each time a little quieter and duller than the last.
BEDS = {
    # Souk Al Seef: birds over the creek-side lane, people far off.
    "fahidi": [
        dict(src=BIRDS, band=(1500, 9000), events=-27.0, expand=24.0, lay="loop", at=0.0),
        dict(src=PEOPLE, band=(300, 2600), events=-44.0, expand=0.0, lay="loop", at=8.0),
    ],
    # Creek Park: a garden, two kinds of birdsong, nobody talking.
    "creek": [
        dict(src=BIRDS, band=(1500, 9000), events=-27.0, expand=24.0, lay="loop", at=0.0),
        dict(src=GARDEN, band=(1800, 8000), events=-31.0, expand=18.0, lay="loop", at=4.0),
    ],
    # Any place without a bed of its own.
    "street": [
        dict(src=BIRDS, band=(1500, 9000), events=-28.0, expand=24.0, lay="loop", at=0.0),
    ],
    # Metro Station: commuters passing, a bird now and then. No traffic.
    "metro": [
        dict(src=PEOPLE, band=(300, 2600), events=-39.0, expand=0.0, lay="loop", at=30.0),
        dict(src=SUNNY, band=(2000, 8000), events=-34.0, expand=20.0, lay="loop", at=2.0),
    ],
    # JBR Beach: small waves arriving one at a time with quiet between them (never a
    # constant wash), a gull far away.
    "jbr": [
        dict(src=WAVES, band=(320, 1500), events=-37.0, expand=22.0, lay="loop", at=-1.0, swell=(6.0, 14.0)),
        dict(src=GULL_A, band=(900, 3800), events=-33.0, expand=14.0, lay="calls", times=(6.0,)),
        dict(src=GULL_B, band=(900, 3800), events=-36.0, expand=14.0, lay="calls", times=(19.5,)),
    ],
    # Downtown: a plaza of quiet talk, sparse birds.
    "downtown": [
        dict(src=PEOPLE, band=(300, 2600), events=-38.0, expand=0.0, lay="loop", at=45.0),
        dict(src=BIRDS, band=(1500, 9000), events=-34.0, expand=24.0, lay="loop", at=0.0),
    ],
    # Mall Food Court: a hall of quiet talk and nothing else (the mall recording itself is
    # mostly escalator machinery, so the restaurant's voices stand in).
    "mall": [
        dict(src=PEOPLE, band=(300, 2600), events=-38.0, expand=0.0, lay="loop", at=22.0),
    ],
    # Global Village: evening crickets coming and going in slow swells, people far off.
    "gv": [
        dict(src=CRICKETS, band=(2200, 7000), events=-38.0, expand=6.0, lay="loop", at=0.0, swell=(7.5, 18.0)),
        dict(src=PEOPLE, band=(300, 2600), events=-42.0, expand=0.0, lay="loop", at=15.0),
    ],
}
# Beds that are only people talking are steady by nature: they pass on being very quiet and
# band-limited to voices instead of on having events.
QUIET_TALK = ["mall"]
# The grill, heard only while an order is cooking: charcoal pops, no frying-oil hiss.
GRILL = [
    dict(src=FIRE, band=(350, 6000), events=-27.0, expand=12.0, lay="calls", times=(0.0, 2.3, 4.4, 6.1)),
    dict(src=EMBERS, band=(700, 6000), events=-36.0, expand=14.0, lay="loop", at=3.0),
]
GRILL_SECONDS = 8.0

# What "not a noise bed" means, checked on every output (50 ms loudness frames).
MAX_FLOOR_DB = -44.0     # the quiet between events (10th percentile)
MIN_RANGE_DB = 9.0       # events stand at least this far above the floor
MAX_RUMBLE_DB = -12.0    # share of energy under 200 Hz
MAX_HISS_FLOOR_DB = -58.0  # the steady part above 4 kHz (birdsong lives there; a constant hiss must not)
MAX_TALK_DB = -37.0      # a people-only bed stays this quiet


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


_cache = {}


def read_mono(rel: str):
    """A source as mono float32 at RATE."""
    if rel in _cache:
        return _cache[rel]
    with open(os.path.join(SRC, rel), "rb") as f:
        raw = f.read()
    if raw.startswith(b"OggS"):
        raw = vorbis_only(raw)
    x, sr = sf.read(io.BytesIO(raw), dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    if sr != RATE:
        n = int(round(len(x) * RATE / sr))
        x = np.interp(np.linspace(0.0, len(x) - 1.0, n), np.arange(len(x)), x).astype(np.float32)
    _cache[rel] = x
    return x


def band_pass(x, lo: float, hi: float):
    """Zero-phase band limit with soft octave-wide edges."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    gain = np.clip(np.log2(np.maximum(f, 1.0) / (lo / 2.0)), 0.0, 1.0) * np.clip(np.log2((hi * 2.0) / np.maximum(f, 1.0)), 0.0, 1.0)
    return np.fft.irfft(spec * gain, len(x)).astype(np.float32)


def frames_db(x, ms: float = 50.0):
    w = int(RATE * ms / 1000.0)
    f = x[:len(x) // w * w].reshape(-1, w)
    return 20.0 * np.log10(np.sqrt(np.mean(np.square(f), axis=1)) + 1e-9)


def expand(x, depth_db: float):
    """Pushes down what lies between the events: below the layer's own floor + 8 dB the gain
    falls 1 dB per dB, to at most `depth_db`, smoothed so nothing pumps or clicks."""
    if depth_db <= 0.0:
        return x
    w = int(RATE * 0.03)
    env = np.sqrt(np.convolve(np.square(x), np.ones(w, dtype=np.float32) / w, mode="same")) + 1e-9
    env_db = 20.0 * np.log10(env)
    threshold = np.percentile(env_db, 35) + 8.0
    cut = np.clip(env_db - threshold, -depth_db, 0.0)
    smooth = int(RATE * 0.12)
    cut = np.convolve(cut, np.hanning(smooth) / np.hanning(smooth).sum(), mode="same")
    return (x * np.power(10.0, cut / 20.0)).astype(np.float32)


def steadiest(x, length: int) -> int:
    """Start of the stretch whose half-second loudness varies least (no shout, no bang)."""
    hop = RATE // 2
    levels = np.array([20.0 * np.log10(np.sqrt(np.mean(np.square(x[i:i + hop]))) + 1e-9) for i in range(0, len(x) - hop, hop)])
    span = max(1, length // hop)
    best, best_score = 0, 1e9
    for i in range(0, max(1, len(levels) - span)):
        w = levels[i:i + span]
        score = float(w.max() - w.min()) + float(w.std())
        if score < best_score:
            best, best_score = i, score
    return best * hop


def looped(x, start_s: float, seconds: float, fade_s: float = 1.5):
    """`seconds` of x from `start_s` (-1 = the steadiest stretch) that repeats without a
    click: the tail crossfades into the head. A source shorter than asked is tiled."""
    n, f = int(seconds * RATE), int(fade_s * RATE)
    while len(x) < n + f + RATE:
        k = min(f, len(x) // 4)
        t = np.linspace(0.0, np.pi / 2.0, k, dtype=np.float32)
        x = np.concatenate([x[:-k], x[-k:] * np.cos(t) + x[:k] * np.sin(t), x[k:]])
    start = steadiest(x, n + f) if start_s < 0.0 else int(start_s * RATE)
    start = max(0, min(start, len(x) - n - f))
    body = x[start:start + n].copy()
    t = np.linspace(0.0, np.pi / 2.0, f, dtype=np.float32)
    body[:f] = body[:f] * np.sin(t) + x[start + n:start + n + f] * np.cos(t)
    return body


def calls(x, times, seconds: float):
    """The clip dropped into silence at each time; later calls are quieter (further away)."""
    out = np.zeros(int(seconds * RATE), dtype=np.float32)
    loud = np.flatnonzero(np.abs(x) > 0.02 * np.abs(x).max())
    clip = x[max(0, loud[0] - 400):min(len(x), loud[-1] + int(0.3 * RATE))].copy()
    edge = int(0.02 * RATE)
    clip[:edge] *= np.linspace(0.0, 1.0, edge, dtype=np.float32)
    clip[-edge:] *= np.linspace(1.0, 0.0, edge, dtype=np.float32)
    for i, at in enumerate(times):
        a = int(at * RATE)
        piece = clip[:max(0, len(out) - a)] * (0.8 ** i)
        if i % 2 == 1:
            piece = piece[::1] * 0.9
        out[a:a + len(piece)] += piece
    return out


def set_events(x, target_db: float):
    """Scales a layer so its events (95th percentile of 50 ms loudness) sit at target_db."""
    now = float(np.percentile(frames_db(x), 95))
    return (x * 10.0 ** ((target_db - now) / 20.0)).astype(np.float32)


def mix(layers, seconds: float):
    out = np.zeros(int(seconds * RATE), dtype=np.float32)
    for layer in layers:
        x = band_pass(read_mono(layer["src"]), *layer["band"])
        x = expand(x, layer["expand"])
        if layer["lay"] == "loop":
            x = looped(x, layer["at"], seconds)
        else:
            x = calls(x, layer["times"], seconds)
        if "swell" in layer:
            # a slow rise and fall that completes whole cycles inside the loop
            period, depth = layer["swell"]
            cycles = max(1, round(seconds / period))
            phase = np.linspace(0.0, 2.0 * np.pi * cycles, len(x), endpoint=False)
            x = (x * np.power(10.0, -depth * (0.5 - 0.5 * np.cos(phase)) / 20.0)).astype(np.float32)
        out += set_events(x, layer["events"])
    peak = float(np.abs(out).max())
    if peak > PEAK:
        out *= PEAK / peak
    return out


def describe(x):
    db = frames_db(x)
    spec = np.square(np.abs(np.fft.rfft(x * np.hanning(len(x)))))
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    share = lambda lo, hi: 10.0 * np.log10(spec[(f >= lo) & (f < hi)].sum() / spec.sum() + 1e-12)
    top = np.fft.irfft(np.fft.rfft(x) * (np.fft.rfftfreq(len(x), 1.0 / RATE) >= 4000.0), len(x))
    return dict(rms=20.0 * np.log10(float(np.sqrt(np.mean(np.square(x)))) + 1e-9), floor=float(np.percentile(db, 10)),
        events=float(np.percentile(db, 95)), rumble=float(share(0, 200)), hiss=float(np.percentile(frames_db(top), 10)),
        seam=float(abs(x[0] - x[-1])))


def write(path: str, x, quality: float = 0.2) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with sf.SoundFile(path, "w", samplerate=RATE, channels=1, format="OGG", subtype="VORBIS",
            compression_level=1.0 - quality) as out:
        for i in range(0, len(x), RATE * 5):  # libsndfile overflows on one very long Vorbis write
            out.write(x[i:i + RATE * 5])


def main() -> int:
    check = "--check" in sys.argv
    jobs = [("assets/sfx/ambience/%s.ogg" % name, layers, SECONDS, name in QUIET_TALK) for name, layers in BEDS.items()]
    jobs.append(("assets/sfx/loops/grill_sizzle.ogg", GRILL, GRILL_SECONDS, False))
    total, failed = 0, 0
    for dst, layers, seconds, talk_only in jobs:
        x = mix(layers, seconds)
        d = describe(x)
        out = os.path.join(ROOT, dst)
        if not check:
            write(out, x)
        size = os.path.getsize(out) if os.path.exists(out) else 0
        total += size
        problems = []
        if talk_only:
            if d["events"] > MAX_TALK_DB:
                problems.append("talk too loud")
        else:
            if d["floor"] > MAX_FLOOR_DB:
                problems.append("floor too loud")
            if d["events"] - d["floor"] < MIN_RANGE_DB:
                problems.append("steady noise, no events")
        if d["rumble"] > MAX_RUMBLE_DB:
            problems.append("rumble")
        if d["hiss"] > MAX_HISS_FLOOR_DB:
            problems.append("steady hiss")
        failed += 1 if problems else 0
        print("%-34s %5.1fs rms %6.1f dB | floor %6.1f events %6.1f (range %4.1f) | under 200 Hz %6.1f steady >4 kHz %6.1f | seam %.3f %6.1f KB  %s" % (
            dst, len(x) / RATE, d["rms"], d["floor"], d["events"], d["events"] - d["floor"], d["rumble"], d["hiss"], d["seam"],
            size / 1024.0, "FAIL: " + ", ".join(problems) if problems else "ok"))
    print("total %.2f MB, %d failed" % (total / 1048576.0, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
