"""Build eleven low-poly, texture-free upgrade/shop icons with Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_icons_c.py
Same conventions as make_icons_a.py: metres, Z up during modeling, +Y up in
GLB, origin at base centre, ~0.4-0.5 m wide, fronts face -Y (Godot +Z).
"""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_furniture import (ROOT, TAU, ball, beam, block, chair, clear_scene,
                            cylinder, export_model, glass, glow, lathe, material,
                            mesh, metal, prism, round_table, tube)


OUTPUT = ROOT / "assets/models/icons"


def mat(name, color, roughness=0.85):
    return bpy.data.materials.get(name) or material(name, color, roughness)


def metal_mat(name, color):
    return bpy.data.materials.get(name) or metal(name, color)


def slab(name, a, b, c, d, thickness, material_):
    """Thin solid from a quad (a,b,c,d anticlockwise from above) pushed down."""
    top = [Vector(p) for p in (a, b, c, d)]
    bottom = [p - Vector((0, 0, thickness)) for p in top]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
             (2, 6, 7, 3), (3, 7, 4, 0)]
    return mesh(name, top + bottom, faces, [material_])


def awning(x0, x1, y_wall, z_top, depth, drop, colours, stripes):
    """Striped awning sloping out from a wall at -Y, with a scalloped valance."""
    parts = []
    width = (x1 - x0) / stripes
    for i in range(stripes):
        a, b = x0 + i * width, x0 + (i + 1) * width
        m = colours[i % len(colours)]
        parts.append(slab("Awning stripe", (a, y_wall - depth, z_top - drop),
                          (b, y_wall - depth, z_top - drop), (b, y_wall, z_top),
                          (a, y_wall, z_top), 0.006, m))
        parts.append(block("Awning valance", (width, 0.006, 0.03),
                           ((a + b) / 2, y_wall - depth, z_top - drop - 0.018), m))
    return parts


def building(width, depth, height, floors, wall, trim, awning_colours, glass_,
             door, sign, stripes):
    parts = [block("Building walls", (width, depth, height), (0, 0, height / 2),
                   wall),
             block("Roof parapet", (width + 0.016, depth + 0.016, 0.022),
                   (0, 0, height + 0.011), trim, 0.003),
             block("Base plinth", (width + 0.008, depth + 0.008, 0.016),
                   (0, 0, 0.008), trim)]
    front = -depth / 2
    floor_h = height / floors
    # Ground floor: door plus shop windows; upper floors get window rows.
    parts.append(block("Front door", (0.07, 0.008, floor_h * 0.68),
                       (0, front - 0.002, floor_h * 0.34 + 0.016), door))
    shop_w = (width - 0.12) / 2 - 0.03
    for side in (-1, 1):
        parts.append(block("Shop window", (shop_w, 0.008, floor_h * 0.5),
                           (side * (0.05 + 0.015 + shop_w / 2), front - 0.002,
                            floor_h * 0.42), glass_))
    for f in range(1, floors):
        z = floor_h * f + floor_h * 0.5
        n = max(2, int(width / 0.1))
        for i in range(n):
            x = -width / 2 + width * (i + 0.5) / n
            parts.append(block("Upper window", (width / n * 0.6, 0.008,
                                                floor_h * 0.5),
                               (x, front - 0.002, z), glass_))
        parts.append(block("Floor band", (width + 0.006, depth + 0.006, 0.012),
                           (0, 0, floor_h * f), trim))
    parts += awning(-width / 2 + 0.01, width / 2 - 0.01, front, floor_h * 0.86,
                    0.07, 0.04, awning_colours, stripes)
    parts.append(block("Rooftop sign", (width * 0.6, 0.02, 0.06),
                       (0, front + 0.03, height + 0.06), sign, 0.004))
    parts.append(block("Sign posts", (width * 0.5, 0.01, 0.03),
                       (0, front + 0.035, height + 0.02), trim))
    return parts


def palette():
    return dict(
        sand=mat("Icons C - sand walls", (0.80, 0.64, 0.42)),
        cream=mat("Icons C - cream", (0.95, 0.88, 0.70)),
        teal=mat("Icons C - teal trim", (0.05, 0.30, 0.32), 0.6),
        red=mat("Icons C - awning red", (0.70, 0.07, 0.05)),
        green=mat("Icons C - awning green", (0.08, 0.45, 0.2)),
        gold=metal_mat("Icons C - gold", (0.88, 0.62, 0.18)),
        glass=mat("Icons C - window glass", (0.25, 0.55, 0.65), 0.2),
        door=mat("Icons C - dark wood", (0.25, 0.12, 0.05), 0.6),
        steel=metal_mat("Icons C - steel", (0.62, 0.66, 0.69)),
        dark=mat("Icons C - charcoal", (0.07, 0.08, 0.09), 0.6),
        teak=mat("Icons C - teak", (0.42, 0.21, 0.08), 0.6),
    )


def build_kiosk():
    p = palette()
    return building(0.36, 0.26, 0.26, 1, p["sand"], p["teal"],
                    [p["red"], p["cream"]], p["glass"], p["door"], p["gold"], 7)


def build_restaurant():
    p = palette()
    return building(0.43, 0.3, 0.32, 1, p["cream"], p["teal"],
                    [p["green"], p["cream"]], p["glass"], p["door"], p["gold"], 9)


def build_flagship():
    p = palette()
    parts = building(0.48, 0.32, 0.46, 2, p["sand"], p["gold"],
                     [p["teal"], p["cream"]], p["glass"], p["door"], p["gold"], 10)
    for x in (-0.22, 0.22):
        parts.append(block("Entrance column", (0.025, 0.025, 0.2),
                           (x, -0.172, 0.1), p["cream"]))
    parts.append(block("Gold cornice", (0.5, 0.012, 0.02), (0, -0.166, 0.44),
                       p["gold"]))
    return parts


def build_fryer():
    p = palette()
    oil = glow("Fryer - hot golden oil", (0.95, 0.62, 0.12), 0.6)
    red = mat("Icons C - red knobs", (0.75, 0.08, 0.05))
    parts = [block("Fryer cabinet", (0.42, 0.26, 0.24), (0, 0, 0.14), p["steel"],
                   0.004),
             block("Fryer top deck", (0.43, 0.27, 0.02), (0, 0, 0.27), p["steel"],
                   0.003),
             block("Fryer control panel", (0.4, 0.01, 0.06), (0, -0.135, 0.22),
                   p["dark"])]
    for x in (-0.18, 0.18):
        for y in (-0.1, 0.1):
            parts.append(block("Fryer leg", (0.025, 0.025, 0.02), (x, y, 0.01),
                               p["dark"]))
    for x in (-0.06, 0.06):
        parts.append(cylinder("Control knob", 0.014, 0.012, (x, -0.145, 0.22),
                              red, segments=8, rotation=(math.pi / 2, 0, 0)))
    for side in (-1, 1):
        x = side * 0.1
        parts.append(block("Oil well", (0.17, 0.2, 0.004), (x, 0.01, 0.281), oil))
        # Wire basket lifted half out of the oil, handle reaching forward.
        parts.append(block("Basket body", (0.14, 0.15, 0.06), (x, 0.02, 0.305),
                           p["dark"], 0.004))
        fries = mat("Icons C - fries", (0.98, 0.78, 0.30), 0.7)
        for i in range(9):
            fx, fy = x - 0.04 + (i % 3) * 0.04, -0.02 + (i // 3) * 0.04
            parts.append(block("Fry stick", (0.014, 0.014, 0.05),
                               (fx, fy, 0.34), fries,
                               rotation=(0.25 * ((i % 2) * 2 - 1), 0.2 * (i % 3 - 1), 0)))
        parts.append(beam("Basket handle", (x, -0.055, 0.32), (x, -0.16, 0.37),
                          0.014, p["dark"]))
        parts.append(block("Handle grip", (0.03, 0.04, 0.025),
                           (x, -0.165, 0.374), red, 0.004))
    return parts


def mini_samovar(brass, dark, scale=1.0):
    s = scale
    parts = [lathe("Samovar body", [(0.04 * s, 0), (0.042 * s, 0.008 * s),
                                    (0.025 * s, 0.02 * s), (0.05 * s, 0.05 * s),
                                    (0.056 * s, 0.075 * s), (0.052 * s, 0.1 * s),
                                    (0.03 * s, 0.118 * s)], [brass], segments=12),
             lathe("Samovar teapot", [(0.02 * s, 0.118 * s), (0.03 * s, 0.13 * s),
                                      (0.012 * s, 0.15 * s), (0.006 * s, 0.16 * s)],
                   [brass], segments=10),
             beam("Samovar tap", (0, -0.05 * s, 0.055 * s),
                  (0, -0.075 * s, 0.048 * s), 0.008 * s, dark)]
    for side in (-1, 1):
        parts.append(tube("Samovar handle", [(side * 0.05 * s, 0, 0.09 * s),
                          (side * 0.07 * s, 0, 0.088 * s),
                          (side * 0.066 * s, 0, 0.07 * s),
                          (side * 0.054 * s, 0, 0.068 * s)], 0.005 * s, dark,
                          sides=5))
    return parts


def cup(x, y, z, glass_, tea, radius=0.022, height=0.045):
    return [lathe("Glass cup", [(radius * 0.8, z), (radius, z + height),
                                (radius * 0.9, z + height), (radius * 0.72, z + 0.004)],
                  [glass_], segments=10),
            cylinder("Karak tea", radius * 0.88, 0.004,
                     (0, 0, z + height * 0.8), tea, segments=10)]


def placed(parts, dx, dy, dz=0):
    for obj in parts:
        obj.location += Vector((dx, dy, dz))
    return parts


def build_karak_station():
    p = palette()
    tea = mat("Icons C - karak tea", (0.62, 0.36, 0.16))
    cupglass = mat("Icons C - cup glass", (0.85, 0.92, 0.94), 0.15)
    parts = [block("Station counter", (0.44, 0.24, 0.12), (0, 0, 0.06), p["teak"],
                   0.004),
             block("Counter top", (0.46, 0.26, 0.015), (0, 0, 0.1275), p["cream"],
                   0.003),
             block("Brass tray", (0.2, 0.14, 0.008), (0.1, -0.02, 0.139),
                   p["gold"], 0.003)]
    parts += placed(mini_samovar(p["gold"], p["dark"], 1.6), -0.1, 0.02, 0.135)
    for i, (x, y) in enumerate(((0.05, -0.05), (0.11, 0.01), (0.15, -0.06))):
        parts += placed(cup(0, 0, 0.143, cupglass, tea), x, y)
    return parts


def build_table_set():
    teak = mat("Icons C - teak", (0.42, 0.21, 0.08), 0.6)
    cream = mat("Icons C - cream", (0.95, 0.88, 0.70))
    top = mat("Icons C - table top", (0.52, 0.28, 0.10), 0.45)
    parts = round_table(0.13, 0.21, top, teak, segments=16)
    parts += chair(-0.19, 1, teak, cream, scale=0.75)
    parts += chair(0.19, -1, teak, cream, scale=0.75)
    return parts


def build_string_lights():
    p = palette()
    warm = glow("Icons C - warm bulbs", (1.0, 0.72, 0.25), 3)
    parts = []
    for x in (-0.22, 0.22):
        parts.append(block("Light post", (0.022, 0.022, 0.42), (x, 0, 0.21),
                           p["teak"]))
        parts.append(block("Post foot", (0.06, 0.06, 0.02), (x, 0, 0.01), p["dark"]))
        parts.append(ball("Post cap", 0.016, (x, 0, 0.425), p["gold"]))
    wire = []
    n = 12
    for i in range(n + 1):
        t = i / n
        x = -0.22 + 0.44 * t
        z = 0.4 - 0.09 * (1 - (2 * t - 1) ** 2)
        wire.append((x, 0, z))
    parts.append(tube("Sagging wire", wire, 0.003, p["dark"], sides=4))
    for i in range(1, n, 2):
        x, _, z = wire[i]
        parts.append(block("Bulb socket", (0.01, 0.01, 0.012), (x, 0, z - 0.008),
                           p["dark"]))
        parts.append(ball("Glowing bulb", 0.013, (x, 0, z - 0.026), warm,
                          scale=(1, 1, 1.3)))
    return parts


def fan_head(hub, guard, blade_mat, radius, hub_z, hub_y):
    parts = [cylinder("Fan hub", radius * 0.2, 0.03, (0, hub_y, hub_z), hub,
                      segments=10, rotation=(math.pi / 2, 0, 0))]
    ring = [(radius * math.cos(TAU * i / 16), hub_y - 0.02,
             hub_z + radius * math.sin(TAU * i / 16)) for i in range(17)]
    parts.append(tube("Fan guard", ring, 0.005, guard, sides=4))
    for i in range(4):
        a = TAU * i / 4 + math.pi / 4
        parts.append(beam("Guard spoke", (0, hub_y - 0.03, hub_z),
                          (radius * math.cos(a), hub_y - 0.02,
                           hub_z + radius * math.sin(a)), 0.004, guard))
    for i in range(3):
        a = TAU * i / 3
        b = block("Fan blade", (radius * 0.45, 0.006, radius * 0.8),
                  (radius * 0.5 * math.sin(a), hub_y + 0.005,
                   hub_z + radius * 0.5 * math.cos(a)), blade_mat, 0.002)
        b.rotation_mode = "ZYX"
        b.rotation_euler = (0, -a, 0.35)
        parts.append(b)
    return parts


def build_misting_fan():
    p = palette()
    water = mat("Icons C - water tank blue", (0.10, 0.45, 0.75), 0.3)
    mist = mat("Icons C - mist white", (0.85, 0.95, 1.0), 0.9)
    parts = [block("Water tank base", (0.2, 0.16, 0.1), (0, 0, 0.05), water, 0.012),
             block("Tank lid", (0.12, 0.1, 0.012), (0, 0.01, 0.106), p["cream"]),
             cylinder("Fan pole", 0.012, 0.2, (0, 0.03, 0.2), p["steel"],
                      segments=8),
             block("Motor housing", (0.06, 0.08, 0.06), (0, 0.05, 0.33), p["cream"],
                   0.01)]
    parts += fan_head(p["cream"], p["steel"], p["teal"], 0.13, 0.33, 0.0)
    # Mist nozzles around the guard and puffs drifting forward.
    for i in range(5):
        a = math.pi / 2 + (i - 2) * 0.5
        x, z = 0.14 * math.cos(a), 0.33 + 0.14 * math.sin(a)
        parts.append(block("Mist nozzle", (0.012, 0.02, 0.012), (x, -0.02, z),
                           p["dark"]))
    for x, y, z, r in ((-0.2, -0.12, 0.33, 0.035), (-0.17, -0.09, 0.42, 0.03),
                       (0.2, -0.12, 0.34, 0.035), (0.17, -0.1, 0.43, 0.028),
                       (0.0, -0.13, 0.49, 0.03), (-0.21, -0.13, 0.24, 0.028),
                       (0.21, -0.13, 0.25, 0.026)):
        parts.append(ball("Mist puff", r, (x, y, z), mist, subdivisions=2))
    return parts


def build_valet():
    p = palette()
    key_tag = mat("Icons C - red key tag", (0.72, 0.08, 0.06))
    podium = prism("Valet podium", [(-0.09, 0.015), (0.09, 0.015), (0.11, 0.36),
                                    (-0.11, 0.36)], 0.18, p["teak"])
    parts = [podium,
             block("Podium plinth", (0.2, 0.2, 0.015), (0, 0, 0.0075), p["dark"]),
             block("Podium desk", (0.24, 0.21, 0.016), (0, 0, 0.37), p["dark"],
                   0.003, rotation=(-0.2, 0, 0)),
             block("Podium brass plate", (0.09, 0.006, 0.04), (0, -0.093, 0.24),
                   p["gold"])]
    # Big gold key standing to the right, leaning on the podium.
    bow = [(0.04 * math.sin(TAU * i / 12), 0, 0.04 * math.cos(TAU * i / 12))
           for i in range(13)]
    key = [tube("Key bow ring", bow, 0.011, p["gold"], sides=6),
           block("Key shaft", (0.02, 0.016, 0.24), (0, 0, -0.16), p["gold"]),
           block("Key bit 1", (0.045, 0.016, 0.02), (0.03, 0, -0.27), p["gold"]),
           block("Key bit 2", (0.035, 0.016, 0.02), (0.025, 0, -0.23), p["gold"]),
           block("Key tag", (0.05, 0.006, 0.035), (-0.05, -0.012, 0.0), key_tag,
                 rotation=(0, 0.5, 0))]
    for obj in key:
        obj.location += Vector((0.23, -0.03, 0.33))
    parts += key
    return parts


def build_juice_bar():
    p = palette()
    orange = mat("Icons C - orange", (0.95, 0.42, 0.04))
    lemon = mat("Icons C - lemon", (0.95, 0.85, 0.15))
    leaf = mat("Icons C - leaf green", (0.15, 0.48, 0.12))
    juice = mat("Icons C - orange juice", (1.0, 0.55, 0.05), 0.3)
    cupglass = mat("Icons C - cup glass", (0.85, 0.92, 0.94), 0.15)
    pine = mat("Icons C - pineapple", (0.80, 0.55, 0.12))
    parts = [block("Juice counter", (0.44, 0.22, 0.18), (0, 0, 0.09), p["green"],
                   0.004),
             block("Juice counter top", (0.46, 0.24, 0.015), (0, 0, 0.1875),
                   p["cream"], 0.003)]
    for i in range(5):
        parts.append(block("Counter stripe", (0.04, 0.006, 0.16),
                           (-0.16 + i * 0.08, -0.112, 0.09), p["cream"]))
    top = 0.195
    # Fruit crate with oranges and lemons on the left.
    parts.append(block("Fruit crate", (0.16, 0.12, 0.04), (-0.13, 0.01, top + 0.02),
                       p["teak"]))
    for i, (x, y) in enumerate(((-0.17, -0.02), (-0.13, -0.02), (-0.09, -0.02),
                                (-0.15, 0.03), (-0.11, 0.035))):
        parts.append(ball("Fruit", 0.022, (x, y, top + 0.05),
                          orange if i % 2 == 0 else lemon))
    parts.append(ball("Top orange", 0.022, (-0.13, 0.005, top + 0.085), orange))
    # Pineapple centre-back.
    parts.append(ball("Pineapple body", 0.035, (0.02, 0.05, top + 0.045), pine,
                      scale=(1, 1, 1.35)))
    for i in range(5):
        a = TAU * i / 5
        parts.append(beam("Pineapple leaf", (0.02, 0.05, top + 0.085),
                          (0.02 + 0.025 * math.cos(a), 0.05 + 0.025 * math.sin(a),
                           top + 0.135), 0.008, leaf, 0.004))
    # Juicer on the right and two juice glasses at the front.
    parts += [lathe("Juicer base", [(0.04, top), (0.04, top + 0.04),
                                    (0.03, top + 0.05)], [p["steel"]], segments=12),
              lathe("Juicer jug", [(0.03, top + 0.05), (0.036, top + 0.13),
                                   (0.032, top + 0.135)], [juice], segments=12),
              cylinder("Juicer lid", 0.037, 0.012, (0, 0, top + 0.141), p["dark"],
                       segments=12)]
    for obj in parts[-3:]:
        obj.location += Vector((0.15, 0.03, 0))
    for x in (0.06, 0.12):
        parts += placed(cup(0, 0, top, cupglass, juice, 0.02, 0.06), x, -0.06)
    return parts


def build_mop_bucket():
    yellow = mat("Icons C - bucket yellow", (0.95, 0.72, 0.05), 0.5)
    p = palette()
    water = mat("Icons C - mop water", (0.25, 0.55, 0.70), 0.2)
    mop = mat("Icons C - mop strands", (0.90, 0.88, 0.80))
    parts = [block("Bucket tub", (0.3, 0.22, 0.17), (0, 0, 0.115), yellow, 0.02),
             block("Bucket rim", (0.31, 0.23, 0.02), (0, 0, 0.2), yellow, 0.006),
             block("Mop water", (0.26, 0.18, 0.006), (0, 0, 0.185), water),
             block("Wringer box", (0.12, 0.2, 0.09), (0.08, 0, 0.245), p["dark"],
                   0.008),
             beam("Wringer lever", (0.12, 0, 0.29), (0.2, 0, 0.42), 0.02, p["dark"])]
    for x in (-0.12, 0.12):
        for y in (-0.08, 0.08):
            parts.append(cylinder("Caster wheel", 0.016, 0.014, (x, y, 0.016),
                                  p["dark"], segments=8,
                                  rotation=(0, math.pi / 2, 0)))
    # Mop leaning out of the bucket to the left.
    parts.append(beam("Mop handle", (-0.06, 0, 0.17), (-0.2, 0.02, 0.6), 0.018,
                      p["teal"]))
    for i in range(8):
        a = TAU * i / 8
        parts.append(beam("Mop strand", (-0.06, 0, 0.19),
                          (-0.06 + 0.05 * math.cos(a), 0.05 * math.sin(a), 0.2),
                          0.016, mop))
    return parts


def main():
    clear_scene()
    for name, builder in [("kiosk", build_kiosk), ("restaurant", build_restaurant),
                          ("flagship", build_flagship), ("fryer", build_fryer),
                          ("karak-station", build_karak_station),
                          ("table-set", build_table_set),
                          ("string-lights", build_string_lights),
                          ("misting-fan", build_misting_fan),
                          ("valet", build_valet), ("juice-bar", build_juice_bar),
                          ("mop-bucket", build_mop_bucket)]:
        export_model(OUTPUT, name, builder(), max_tris=1500, width=(0.36, 0.52))
    print("Finished icon set C exports.", flush=True)


if __name__ == "__main__":
    main()
