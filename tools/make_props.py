"""Build nine low-poly, texture-free decor props with Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_props.py
Metres, Z up during modeling, +Y up in GLB, fronts face -Y (glTF/Godot +Z).
Origins are at the base centre of the bounding box.

Swappable surfaces (material names in the GLB):
  lantern.glb   "Lantern - amber glass"  (make emissive at night)
  fountain.glb  "Fountain - water"
  neon-frame    "Neon frame - pink tube" (already emissive)
  pylon-sign    "Pylon - sign face"
pedestal-fan.glb has two nodes, `base` and `head`; `head` (blades + hub) has
its origin on the hub and spins about its local Z axis (Godot) / -Y (Blender).
"""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_furniture import (ROOT, TAU, ball, beam, block, clear_scene, cylinder,
                            export_model, glass, glow, lathe, material, mesh,
                            metal, prism, tube)


OUTPUT = ROOT / "assets/models/props"


def brass_mat():
    return bpy.data.materials.get("Props - brass") or metal(
        "Props - brass", (0.80, 0.55, 0.18))


def build_lantern():
    brass = brass_mat()
    amber = material("Lantern - amber glass", (1.0, 0.55, 0.12), 0.3)
    parts = [lathe("Lantern base", [(0.05, 0), (0.06, 0.012), (0.06, 0.022),
                                    (0.052, 0.03)], [brass], segments=6),
             lathe("Lantern amber glass panels", [(0.051, 0.03), (0.056, 0.09),
                                                  (0.056, 0.12), (0.044, 0.15)],
                   [amber], segments=6),
             lathe("Lantern dome", [(0.058, 0.148), (0.058, 0.156),
                                    (0.04, 0.178), (0.012, 0.196),
                                    (0.008, 0.198)], [brass], segments=6),
             cylinder("Lantern finial", 0.006, 0.012, (0, 0, 0.204), brass,
                      segments=6)]
    ring = tube("Lantern hanging ring",
                [(0.0, 0, 0.21)] + [(0.011 * math.sin(TAU * i / 8), 0,
                                     0.21 + 0.011 * (1 - math.cos(TAU * i / 8)))
                                    for i in range(1, 9)], 0.0025, brass, sides=4)
    parts.append(ring)
    # Corner ribs and a mid band over the glass; the panels stay one surface.
    for i in range(6):
        a = TAU * i / 6
        parts.append(beam("Lantern corner rib",
                          (0.053 * math.cos(a), 0.053 * math.sin(a), 0.03),
                          (0.058 * math.cos(a), 0.058 * math.sin(a), 0.09), 0.005,
                          brass))
        parts.append(beam("Lantern upper rib",
                          (0.058 * math.cos(a), 0.058 * math.sin(a), 0.12),
                          (0.046 * math.cos(a), 0.046 * math.sin(a), 0.15), 0.005,
                          brass))
    parts.append(lathe("Lantern brass band", [(0.059, 0.09), (0.059, 0.12),
                                              (0.0575, 0.12), (0.0575, 0.09)],
                       [brass], segments=6))
    return parts


def build_samovar():
    brass = brass_mat()
    dark = material("Samovar - black grips", (0.06, 0.05, 0.045))
    parts = [lathe("Samovar body", [(0.04, 0), (0.042, 0.008), (0.025, 0.02),
                                    (0.022, 0.03), (0.05, 0.05), (0.056, 0.075),
                                    (0.052, 0.1), (0.035, 0.112), (0.03, 0.118)],
                   [brass], segments=14),
             lathe("Samovar teapot", [(0.02, 0.118), (0.03, 0.13), (0.028, 0.142),
                                      (0.012, 0.15), (0.006, 0.16)],
                   [brass], segments=12)]
    # Tap at the front with a black key.
    parts.append(beam("Samovar tap spout", (0, -0.05, 0.055), (0, -0.075, 0.048),
                      0.008, brass))
    parts.append(block("Samovar tap key", (0.018, 0.005, 0.006),
                       (0, -0.07, 0.056), dark))
    for side in (-1, 1):
        parts.append(tube("Samovar side handle",
                          [(side * 0.05, 0, 0.09), (side * 0.068, 0, 0.092),
                           (side * 0.072, 0, 0.08), (side * 0.066, 0, 0.07),
                           (side * 0.054, 0, 0.068)], 0.004, dark, sides=5))
    return parts


def build_dallah():
    brass = brass_mat()
    parts = [lathe("Dallah body", [(0.034, 0), (0.036, 0.004), (0.034, 0.012),
                                   (0.022, 0.03), (0.016, 0.042), (0.02, 0.055),
                                   (0.026, 0.07), (0.024, 0.078), (0.016, 0.08)],
                   [brass], segments=14),
             lathe("Dallah lid", [(0.017, 0.08), (0.02, 0.088), (0.016, 0.096),
                                  (0.008, 0.1), (0.004, 0.106)], [brass],
                   segments=12),
             ball("Dallah finial", 0.006, (0, 0, 0.112), brass, scale=(1, 1, 1.5))]
    # Signature crescent beak spout sweeping up from the waist.
    parts.append(tube("Dallah beak spout",
                      [(-0.012, 0, 0.044), (-0.028, 0, 0.058), (-0.038, 0, 0.076),
                       (-0.044, 0, 0.09), (-0.054, 0, 0.098)], 0.005, brass,
                      sides=6))
    parts.append(tube("Dallah handle",
                      [(0.02, 0, 0.074), (0.036, 0, 0.078), (0.04, 0, 0.06),
                       (0.036, 0, 0.035), (0.026, 0, 0.024)], 0.003, brass,
                      sides=5))
    return parts


def build_neon_frame():
    pink = glow("Neon frame - pink tube", (1.0, 0.08, 0.55), 4)
    clip = material("Neon frame - dark clips", (0.06, 0.07, 0.09))
    r, hw, hh, cr = 0.012, 0.6 - 0.012, 0.15 - 0.012, 0.03
    pts = []
    for cx, cz, start in ((hw - cr, hh - cr, 0), (-hw + cr, hh - cr, 90),
                          (-hw + cr, -hh + cr, 180), (hw - cr, -hh + cr, 270)):
        for k in range(4):
            a = math.radians(start + k * 30)
            pts.append((cx + cr * math.cos(a), 0, 0.15 + cz + cr * math.sin(a)))
    pts.append(pts[0])
    parts = [tube("Pink neon rectangle", pts, r, pink, sides=6)]
    for x in (-0.4, 0, 0.4):
        for z in (0.012, 0.288):
            parts.append(block("Neon tube clip", (0.02, 0.03, 0.03),
                               (x, 0.012, z), clip))
    return parts


def build_fountain():
    stone = material("Fountain - sandstone", (0.55, 0.40, 0.25), 0.9)
    trim = material("Fountain - pale stone rim", (0.74, 0.62, 0.45), 0.9)
    water = material("Fountain - water", (0.18, 0.55, 0.70), 0.1)
    parts = [lathe("Fountain basin wall", [(0.43, 0), (0.44, 0.02), (0.43, 0.26),
                                           (0.45, 0.27), (0.45, 0.3), (0.39, 0.3),
                                           (0.39, 0.06)], [stone], segments=24)]
    parts.append(cylinder("Fountain water", 0.392, 0.01, (0, 0, 0.235), water,
                          segments=24))
    parts.append(lathe("Fountain centre column", [(0.07, 0.06), (0.07, 0.1),
                                                  (0.045, 0.13), (0.04, 0.38),
                                                  (0.06, 0.4)], [stone],
                       segments=12))
    parts.append(lathe("Fountain top bowl", [(0.06, 0.4), (0.13, 0.43),
                                             (0.14, 0.45), (0.12, 0.45),
                                             (0.05, 0.44)], [trim], segments=16))
    parts.append(cylinder("Fountain top bowl water", 0.122, 0.006, (0, 0, 0.444),
                          water, segments=16))
    parts.append(lathe("Fountain spout", [(0.025, 0.44), (0.02, 0.48),
                                          (0.012, 0.5), (0.004, 0.52)], [trim],
                       segments=8))
    for i in range(8):
        a = TAU * i / 8
        parts.append(block("Fountain wall panel", (0.12, 0.012, 0.16),
                           (0.443 * math.cos(a), 0.443 * math.sin(a), 0.13), trim,
                           rotation=(0, 0, a + math.pi / 2)))
    return parts


def build_valet_stand():
    teak = material("Valet - teak", (0.36, 0.17, 0.065), 0.55)
    dark = material("Valet - dark trim", (0.10, 0.10, 0.12), 0.6)
    brass = brass_mat()
    red = material("Valet - red key tags", (0.75, 0.10, 0.08))
    blue = material("Valet - blue key tags", (0.10, 0.30, 0.70))
    # Tapered podium (wider at the top) built as a prism contour.
    body = prism("Valet podium", [(-0.12, 0.02), (0.12, 0.02), (0.15, 0.82),
                                  (-0.15, 0.82)], 0.24, teak)
    parts = [body,
             block("Valet plinth", (0.27, 0.27, 0.02), (0, 0, 0.01), dark),
             block("Valet desk top", (0.3, 0.3, 0.025), (0, 0.01, 0.84), dark,
                   0.004, rotation=(-0.2, 0, 0)),
             block("Valet desk lip", (0.3, 0.012, 0.02), (0, -0.146, 0.875), brass)]
    # Key board on the front face: dark panel, brass hooks and coloured tags.
    parts.append(block("Valet key board", (0.2, 0.012, 0.2), (0, -0.13, 0.63),
                       dark, 0.003))
    for row, z in enumerate((0.69, 0.6)):
        for i in range(4):
            x = -0.066 + i * 0.044
            parts.append(block("Key hook", (0.006, 0.02, 0.006),
                               (x, -0.142, z), brass))
            parts.append(block("Key", (0.01, 0.004, 0.024),
                               (x, -0.15, z - 0.018), brass))
            parts.append(block("Key tag", (0.022, 0.005, 0.03),
                               (x, -0.151, z - 0.047),
                               red if (i + row) % 2 else blue))
    parts.append(block("Valet brass plate", (0.14, 0.008, 0.05), (0, -0.124, 0.38),
                       brass, 0.003))
    return parts


def build_pedestal_fan():
    white = material("Fan - cream enamel", (0.90, 0.88, 0.80), 0.5)
    grey = metal("Fan - steel", (0.55, 0.58, 0.6))
    blade = material("Fan - teal blades", (0.12, 0.45, 0.48), 0.5)
    hub_z, hub_y = 0.5, -0.07
    base = [lathe("Fan round base", [(0.11, 0), (0.11, 0.015), (0.09, 0.03),
                                     (0.02, 0.035)], [white], segments=16),
            cylinder("Fan pole", 0.012, 0.42, (0, 0, 0.24), grey, segments=8),
            lathe("Fan motor housing", [(0.03, -0.06), (0.045, -0.04),
                                        (0.045, 0.02), (0.03, 0.05)],
                  [white], segments=12),
            block("Fan neck", (0.03, 0.03, 0.05), (0, 0, hub_z - 0.04), white)]
    base[2].rotation_euler = (math.pi / 2, 0, 0)
    base[2].location = (0, 0.0, hub_z)
    # Guard ring and spokes stay on the base so only the blades spin.
    ring = [(0.13 * math.cos(TAU * i / 20), hub_y - 0.01,
             hub_z + 0.13 * math.sin(TAU * i / 20)) for i in range(21)]
    base.append(tube("Fan guard ring", ring, 0.004, grey, sides=4))
    for i in range(6):
        a = TAU * i / 6
        base.append(beam("Fan guard spoke", (0, hub_y - 0.025, hub_z),
                         (0.128 * math.cos(a), hub_y - 0.01,
                          hub_z + 0.128 * math.sin(a)), 0.003, grey))
    head = [cylinder("Fan hub", 0.025, 0.03, (0, hub_y + 0.02, hub_z), white,
                     segments=12, rotation=(math.pi / 2, 0, 0))]
    for i in range(3):
        a = TAU * i / 3
        b = block("Fan blade", (0.05, 0.006, 0.11),
                  (0.065 * math.sin(a), hub_y + 0.02, hub_z + 0.065 * math.cos(a)),
                  blade, 0.002)
        b.rotation_mode = "ZYX"
        b.rotation_euler = (0, -a, 0.35)
        head.append(b)
    return dict(groups={"base": base, "head": head},
                pivots={"head": (0, hub_y + 0.02, hub_z)})


def crescent_contour(radius, cut_radius, cut_dx, steps=16):
    """Outer circle minus an offset circle, opening to +X."""
    # Intersection angles of the two circles.
    x = (radius ** 2 - cut_radius ** 2 + cut_dx ** 2) / (2 * cut_dx)
    z = math.sqrt(radius ** 2 - x ** 2)
    a0 = math.atan2(z, x)
    b0 = math.atan2(z, x - cut_dx)
    pts = []
    for k in range(steps + 1):
        a = a0 + (TAU - 2 * a0) * k / steps
        pts.append((radius * math.cos(a), radius * math.sin(a)))
    for k in range(1, steps):
        b = -b0 - (TAU - 2 * b0) * k / steps
        pts.append((cut_dx + cut_radius * math.cos(b), cut_radius * math.sin(b)))
    return pts


def star_contour(r_out, r_in, cx, cz):
    return [(cx + (r_out if k % 2 == 0 else r_in) * math.cos(math.pi / 2 + k * math.pi / 5),
             cz + (r_out if k % 2 == 0 else r_in) * math.sin(math.pi / 2 + k * math.pi / 5))
            for k in range(10)]


def build_crescent():
    gold = metal("Crescent - gold", (0.95, 0.70, 0.22))
    zc = 0.185
    moon = [(x, z + zc) for x, z in crescent_contour(0.11, 0.095, 0.05)]
    parts = [prism("Crescent moon", moon, 0.03, gold),
             prism("Crescent star", star_contour(0.04, 0.017, 0.06, zc), 0.024,
                   gold),
             cylinder("Finial rod", 0.008, 0.085, (0, 0, 0.0425), gold,
                      segments=8),
             ball("Finial ball", 0.02, (0, 0, 0.04), gold)]
    return parts


def build_pylon_sign():
    post = material("Pylon - dark teal post", (0.05, 0.20, 0.22), 0.6)
    gold = metal("Pylon - gold frame", (0.85, 0.62, 0.2))
    face = material("Pylon - sign face", (0.95, 0.88, 0.70))
    parts = [block("Pylon footing", (0.18, 0.18, 0.04), (0, 0, 0.02), post, 0.004),
             block("Pylon post", (0.07, 0.07, 0.95), (0, 0, 0.475), post),
             block("Pylon board frame", (0.6, 0.06, 0.25), (0, 0, 1.075), gold,
                   0.006),
             block("Pylon board face front", (0.56, 0.004, 0.21),
                   (0, -0.031, 1.075), face),
             block("Pylon board face back", (0.56, 0.004, 0.21),
                   (0, 0.031, 1.075), face)]
    return parts


def main():
    clear_scene()
    for name, builder in [("lantern", build_lantern), ("samovar", build_samovar),
                          ("dallah", build_dallah), ("neon-frame", build_neon_frame),
                          ("fountain", build_fountain),
                          ("valet-stand", build_valet_stand),
                          ("pedestal-fan", build_pedestal_fan),
                          ("crescent", build_crescent),
                          ("pylon-sign", build_pylon_sign)]:
        result = builder()
        if isinstance(result, dict):
            export_model(OUTPUT, name, **result)
        else:
            export_model(OUTPUT, name, result)
    print("Finished prop exports.", flush=True)


if __name__ == "__main__":
    main()
