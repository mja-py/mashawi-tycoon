"""Build five low-poly, texture-free BBQ props with Blender 5.2.

Run from any directory: blender -b -P /path/to/tools/make_skewers.py
Metres, Z up while modeling, +Y up in GLB; origins at base centre.
All five exports finish before the 512 x 512 EEVEE previews start.
Optional: -- --no-previews (exports and validation still run).
"""

import json
import math
from pathlib import Path
import random
import struct
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_mashawi import (OUTPUT, PREVIEWS, TAU, box, export_asset, fleck,
                          material, meat_cube, mesh, metal, onion_ring, oval,
                          place, preview, skewer, transform)


def bread_strip(rng):
    wheat = material("Khubz strip - pale wheat", (0.84, 0.66, 0.40))
    toast = material("Khubz strip - toasted freckles", (0.46, 0.27, 0.12))
    bread = oval("Small strip of flat khubz", [
        (0.180, 0), (0.236, 0.002), (0.243, 0.006),
        (0.231, 0.011), (0.170, 0.012)],
        [wheat], segments=16, ratio=0.31, wobble=0.016)
    parts = [bread]
    # Spots stay on the flat top, visible alongside the meat.
    for i in range(12):
        x = (i // 2 - 2.5) * 0.052
        y = (-1 if i % 2 else 1) * rng.uniform(0.042, 0.048)
        parts.append(fleck(f"Bread toast patch {i + 1}", x, y, 0.0123,
                           rng.uniform(0.003, 0.006), toast, rng))
    return parts


def blade(steel, wide=False):
    obj = skewer("Single flat pointed metal skewer", 0.600, steel)
    obj.scale.y = 2.8 if wide else 1.6
    return transform(obj, (0, 0, 0.051))


def build_cubed_skewer(chicken=True):
    label = "Chicken tikka" if chicken else "Mutton tikka"
    rng = random.Random(531 if chicken else 743)
    parts = bread_strip(rng)
    steel = metal(f"{label} - stainless blade")
    parts.append(blade(steel))
    if chicken:
        colors = [material("Chicken - pale orange yogurt marinade", (0.94, 0.61, 0.27)),
                  material("Chicken - light yellow cut", (0.99, 0.76, 0.40)),
                  material("Chicken - golden edges", (0.82, 0.43, 0.16))]
        char = material("Chicken - light brown char patches", (0.34, 0.18, 0.075))
    else:
        colors = [material("Mutton - dark reddish brown", (0.29, 0.085, 0.050)),
                  material("Mutton - warm cut", (0.40, 0.14, 0.075)),
                  material("Mutton - mahogany", (0.23, 0.060, 0.032))]
        char = material("Mutton - charred edges", (0.085, 0.033, 0.018))
    for i in range(6):
        dims = (0.060, rng.uniform(0.067, 0.074), rng.uniform(0.076, 0.083))
        group = meat_cube(f"{label} cube {i + 1}", dims, colors, rng)
        chunk = group[0]
        chunk.data.materials.append(char)
        if not chicken:
            # Cut-corner bevel faces get char; the broad cut faces stay reddish.
            for face in chunk.data.polygons:
                if max(abs(c) for c in face.normal) < 0.99:
                    face.material_index = len(colors)
        for j in range(2):
            group.append(fleck(f"{label} flat char patch {i + 1}-{j + 1}",
                               (j - 0.5) * 0.020, (j - 0.5) * 0.018,
                               dims[2] / 2 + 0.0003,
                               0.006 if chicken else 0.008, char, rng))
        # A second patch sits on the visible vertical face.
        group.extend(place([fleck(f"{label} side sear {i + 1}", 0, 0, 0,
                                   0.007, char, rng)],
                           (0.005, -dims[1] / 2 - 0.0003, 0.004),
                           (math.pi / 2, 0, 0)))
        parts.extend(place(group, ((i - 2.5) * 0.074, 0, 0.012 - (-dims[2] / 2)),
                           (0, 0, rng.uniform(-0.075, 0.075))))
    if chicken:
        green = material("Pepper - bright grilled green", (0.19, 0.42, 0.055))
        dark = material("Pepper - dark green skin", (0.07, 0.23, 0.025))
        for i, x in enumerate((-0.148, 0.074)):
            pepper = box(f"Green pepper piece {i + 1}", (0.013, 0.073, 0.058),
                         green, 0.005)
            pepper.data.materials.append(dark)
            for face in pepper.data.polygons:
                if face.normal.y < -0.9:
                    face.material_index = 1
            parts.append(transform(pepper, (x, 0, 0.043), (0.08, 0, 0)))
    else:
        purple = material("Onion piece - purple outer skin", (0.47, 0.12, 0.30))
        ivory = material("Onion piece - ivory flesh", (0.93, 0.84, 0.76))
        onion = onion_ring("Onion piece threaded between mutton cubes", purple, ivory)
        parts.append(transform(onion, (0, 0, 0.049), (0, math.pi / 2, 0)))
    return parts


def build_chicken_skewer():
    return build_cubed_skewer(True)


def build_mutton_skewer():
    return build_cubed_skewer(False)


def build_kebab_skewer():
    rng = random.Random(1127)
    parts = bread_strip(rng)
    parts.append(blade(metal("Kebab - wide flat stainless blade"), wide=True))
    colors = [material("Kebab - brownish red mince", (0.36, 0.13, 0.075)),
              material("Kebab - warm ridges", (0.45, 0.19, 0.11)),
              material("Kebab - pressed grooves", (0.25, 0.080, 0.043))]
    parsley = material("Kebab - green parsley specks", (0.12, 0.32, 0.045))
    # Paired shoulders around seven shallow indentations are actual finger grooves.
    profile = [(-0.216, 0.45), (-0.204, 0.83)]
    for i in range(7):
        x = -0.174 + i * 0.058
        profile.extend([(x - 0.012, 1.0), (x, 0.87), (x + 0.012, 1.0)])
    profile += [(0.204, 0.83), (0.216, 0.45)]
    n, radius, center_z = 8, 0.049, 0.055
    vertices = [(x, radius * width * math.cos(i * TAU / n),
                 center_z + radius * width * 0.85 * math.sin(i * TAU / n))
                for x, width in profile for i in range(n)]
    faces = [tuple(reversed(range(n)))]
    indices = [0]
    for ring in range(len(profile) - 1):
        for i in range(n):
            faces.append((ring * n + i, ring * n + (i + 1) % n,
                          (ring + 1) * n + (i + 1) % n, (ring + 1) * n + i))
            indices.append(2 if profile[ring + 1][1] == 0.87 else rng.randrange(2))
    faces.append(tuple((len(profile) - 1) * n + i for i in range(n)))
    indices.append(0)
    parts.append(mesh("Long kebab with finger-press ridges", vertices, faces,
                      colors, indices))
    # Place flecks on known ring vertices/facets, including within the grooves.
    for i in range(15):
        x, width = profile[2 + i % 20]
        side = -1 if i % 2 else 1
        y = side * radius * width * 0.30
        z = center_z + radius * width * 0.85 - abs(y) * 0.85 * math.tan(math.pi / 8)
        parts.extend(place([fleck(f"Kebab parsley {i + 1}", 0, 0, 0,
                                   0.0028, parsley, rng)],
                           (x, y, z + 0.0004),
                           (-side * math.atan(0.85 * math.tan(math.pi / 8)), 0, 0)))
    return parts


def roll_shell(name, profile, mats, n=12, cap_bottom=False):
    """Open ended tube for bread/paper; final rings turn inward at the cut lip."""
    vertices = [(r * math.cos(i * TAU / n), r * math.sin(i * TAU / n), z)
                for r, z in profile for i in range(n)]
    faces, indices = [], []
    if cap_bottom:
        faces.append(tuple(reversed(range(n))))
        indices.append(0)
    for ring in range(len(profile) - 1):
        for i in range(n):
            faces.append((ring * n + i, ring * n + (i + 1) % n,
                          (ring + 1) * n + (i + 1) % n, (ring + 1) * n + i))
            indices.append(min(ring, len(mats) - 1))
    return mesh(name, vertices, faces, mats, indices)


def sandwich_half(index, mats, rng):
    wheat, crumb, toast, paper, red, salad, tomato, chicken, char = mats
    # Two 17.5 cm halves reconstruct a 35 cm rolled khubz sandwich.
    parts = [roll_shell(f"Sandwich half {index} - rolled khubz", [
        (0.049, 0), (0.056, 0.030), (0.058, 0.160), (0.057, 0.175),
        (0.048, 0.175), (0.047, 0.158)], [wheat, wheat, wheat, crumb, crumb],
        cap_bottom=True)]
    # Layered bread seam reads as a roll, without any image texture.
    seam = box(f"Half {index} bread overlap", (0.016, 0.003, 0.127), wheat, 0.001)
    parts.append(transform(seam, (0.018, -0.054, 0.089), (0, 0, 0.10)))
    parts.append(roll_shell(f"Half {index} white paper base wrapper", [
        (0.051, 0), (0.059, 0.030), (0.061, 0.097),
        (0.058, 0.104), (0.056, 0.098)], [paper], cap_bottom=True))
    parts.append(roll_shell(f"Half {index} red paper band", [
        (0.0602, 0.048), (0.0608, 0.065)], [red]))
    # Front-facing toasted patches cling to the exposed cylindrical bread facets.
    for i in range(6):
        angle = (-3 + i) * TAU / 12
        group = [fleck(f"Half {index} toasted bread patch {i + 1}", 0, 0, 0,
                       rng.uniform(0.003, 0.005), toast, rng)]
        parts.extend(place(group, (0.0562 * math.cos(angle),
                                   0.0562 * math.sin(angle), 0.126 + (i % 2) * 0.023),
                           (math.pi / 2, 0, angle + math.pi / 2)))
    # Crinkled salad and discrete chicken/tomato chunks fill the open cut face.
    verts = [(0, 0, 0.168)]
    verts += [(0.046 * math.cos(i * TAU / 16),
               0.046 * math.sin(i * TAU / 16), 0.175 + (i % 3) * 0.002)
              for i in range(16)]
    faces = [(0, i + 1, (i + 1) % 16 + 1) for i in range(16)]
    parts.append(mesh(f"Half {index} ruffled green salad", verts, faces, [salad]))
    for i, (x, y) in enumerate([(-0.021, -0.019), (0.015, -0.022),
                               (-0.016, 0.015), (0.020, 0.017)]):
        group = meat_cube(f"Half {index} visible chicken tikka {i + 1}",
                          (0.025, 0.026, 0.019), [chicken, crumb], rng)
        group.append(fleck(f"Half {index} chicken sear {i + 1}", 0.002, 0,
                           0.0098, 0.004, char, rng))
        parts.extend(place(group, (x, y, 0.176), (0, 0, i * 0.41)))
    for i, (x, y) in enumerate([(0, -0.037), (-0.036, 0), (0.032, 0.001)]):
        chunk = box(f"Half {index} red tomato piece {i + 1}",
                    (0.019, 0.012, 0.016), tomato, 0.003)
        parts.append(transform(chunk, (x, y, 0.176), (0, 0, i * 1.1)))
    return parts


def rest_group(parts, x, y, rotation):
    """Rest a rotated assembly exactly on the ground without flattening its base."""
    matrix = Euler(rotation).to_matrix()
    low = min((matrix @ (obj.matrix_basis @ vertex.co)).z
              for obj in parts for vertex in obj.data.vertices)
    return place(parts, (x, y, -low), rotation)


def build_sandwich():
    rng = random.Random(1733)
    mats = [material("Sandwich - golden khubz", (0.83, 0.62, 0.34)),
            material("Sandwich - pale bread cut edge", (0.97, 0.84, 0.58)),
            material("Sandwich - toasted brown freckles", (0.45, 0.25, 0.10)),
            material("Sandwich - white paper", (0.96, 0.95, 0.91)),
            material("Sandwich - red paper band", (0.72, 0.045, 0.025)),
            material("Sandwich - salad green", (0.20, 0.47, 0.065)),
            material("Sandwich - tomato red", (0.86, 0.075, 0.025)),
            material("Sandwich - chicken tikka", (0.96, 0.59, 0.23)),
            material("Sandwich - chicken char", (0.29, 0.13, 0.045))]
    parts = []
    # Outward leaning cut faces show both fillings; the pair spans about 35 cm.
    for i, side in enumerate((-1, 1)):
        parts.extend(rest_group(sandwich_half(i + 1, mats, rng),
                                side * 0.058, 0, (0, side * 0.45, side * 0.08)))
    return parts


def extrude_front(name, outline, front, thickness, mat):
    """Extrude an X/Z silhouette; negative Y is the visible front of the sack."""
    n = len(outline)
    area = sum(outline[i][0] * outline[(i + 1) % n][1]
               - outline[(i + 1) % n][0] * outline[i][1] for i in range(n))
    if area < 0:
        outline = list(reversed(outline))
    vertices = [(x, y, z) for y in (front, front + thickness) for x, z in outline]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    return mesh(name, vertices, faces, [mat])


def build_charcoal():
    rng = random.Random(2017)
    kraft = material("Charcoal sack - kraft brown paper", (0.56, 0.35, 0.16))
    light = material("Charcoal sack - lit paper folds", (0.69, 0.46, 0.23))
    dark = material("Charcoal sack - gusset shadow", (0.39, 0.23, 0.095))
    black = material("Charcoal - black carbon", (0.018, 0.022, 0.025))
    coal_gray = material("Charcoal - fractured facets", (0.060, 0.067, 0.072))
    orange = material("Charcoal sack - orange flame logo", (1.0, 0.24, 0.015))
    # Rectangular sack becomes pinched at the neck; extra corner vertices form gussets.
    outline = [(-1, -0.72), (-0.78, -1), (0.78, -1), (1, -0.72),
               (1, 0.72), (0.78, 1), (-0.78, 1), (-1, 0.72)]
    profile = [(0.086, 0.054, 0), (0.096, 0.062, 0.030),
               (0.092, 0.059, 0.215), (0.083, 0.024, 0.264),
               (0.085, 0.012, 0.284)]
    vertices = [(x * hx, y * hy, z) for hx, hy, z in profile for x, y in outline]
    faces, indices = [tuple(reversed(range(8)))], [2]
    for ring in range(len(profile) - 1):
        for i in range(8):
            faces.append((ring * 8 + i, ring * 8 + (i + 1) % 8,
                          (ring + 1) * 8 + (i + 1) % 8, (ring + 1) * 8 + i))
            indices.append(0 if i in (1, 5) else (1 if i % 2 == 0 else 2))
    faces.append(tuple(range(32, 40)))
    indices.append(1)
    parts = [mesh("Kraft paper charcoal sack with folded gussets", vertices, faces,
                  [kraft, light, dark], indices)]
    fold = box("Sack rolled-over folded top", (0.176, 0.026, 0.018), light, 0.003)
    parts.append(transform(fold, (0, -0.004, 0.289), (0.10, 0, 0)))
    lip = box("Folded paper top seam", (0.168, 0.003, 0.006), dark)
    parts.append(transform(lip, (0, -0.018, 0.286)))
    # Solid orange emblem, no label image or font dependency.
    flame = [(-0.005, 0.085), (-0.029, 0.099), (-0.035, 0.122),
             (-0.019, 0.147), (-0.018, 0.127), (-0.004, 0.144),
             (0.007, 0.183), (0.029, 0.151), (0.035, 0.125),
             (0.024, 0.098), (0.008, 0.085)]
    # Front slopes gently back toward the neck, so place the logo ahead of all of it.
    parts.append(extrude_front("Simple orange flame logo", flame, -0.063, 0.001, orange))
    for i, (x, y, scale) in enumerate([
            (-0.053, -0.082, (0.045, 0.037, 0.035)),
            (0.006, -0.092, (0.055, 0.041, 0.038)),
            (0.059, -0.086, (0.041, 0.033, 0.032)),
            (-0.018, -0.132, (0.038, 0.031, 0.028)),
            (0.078, -0.125, (0.031, 0.026, 0.025))]):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
        lump = bpy.context.object
        lump.name = f"Spilled angular charcoal lump {i + 1}"
        lump.data.materials.append(black)
        lump.data.materials.append(coal_gray)
        for vertex in lump.data.vertices:
            vertex.co *= rng.uniform(0.83, 1.16)
            vertex.co.x *= scale[0]
            vertex.co.y *= scale[1]
            vertex.co.z *= scale[2]
        for face in lump.data.polygons:
            face.material_index = int(rng.random() < 0.27)
        rotation = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), i * 0.9)
        parts.extend(rest_group([lump], x, y, rotation))
    return parts


def checked_export(parts, name, expected):
    """Enforce the stricter budget before reusing the reference export helper."""
    assert parts and len({obj.as_pointer() for obj in parts}) == len(parts)
    bpy.context.view_layer.update()
    coordinates = [obj.matrix_world @ vertex.co
                   for obj in parts for vertex in obj.data.vertices]
    low = Vector(tuple(min(v[i] for v in coordinates) for i in range(3)))
    high = Vector(tuple(max(v[i] for v in coordinates) for i in range(3)))
    offset = Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
    for obj in parts:
        obj.location += offset
        obj.data.calc_loop_triangles()
        assert all(not face.use_smooth for face in obj.data.polygons), name
        assert not obj.modifiers, f"{name}: unapplied modifier"
    triangles = sum(len(obj.data.loop_triangles) for obj in parts)
    assert 0 < triangles < 2000, f"{name}: {triangles} triangles exceeds budget"
    bpy.context.view_layer.update()
    obj = export_asset(parts, name, expected)
    bounds = [vertex.co for vertex in obj.data.vertices]
    for axis in (0, 1):
        assert abs(min(v[axis] for v in bounds) + max(v[axis] for v in bounds)) < 1e-5
    # Check the actual GLB as well as the in-memory Blender geometry.
    path = OUTPUT / f"{name}.glb"
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert (magic, version, length) == (b"glTF", 2, len(data)), name
    chunk_length, chunk_type = struct.unpack_from("<I4s", data, 12)
    assert chunk_type == b"JSON", name
    document = json.loads(data[20:20 + chunk_length])
    assert len(document["meshes"]) == 1 and len(document["nodes"]) == 1, name
    assert not document.get("images") and not document.get("textures"), name
    actual = 0
    for primitive in document["meshes"][0]["primitives"]:
        assert primitive.get("mode", 4) == 4, name
        count = document["accessors"][primitive["indices"]]["count"]
        assert count % 3 == 0, name
        actual += count // 3
    assert actual == triangles and actual < 2000, (name, actual, triangles)
    print(f"Validated {path.name}: {actual} exported triangles, no textures.", flush=True)
    return obj


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    assets = []
    for builder, name, image, expected in [
            (build_chicken_skewer, "chicken-skewer", "chicken_skewer_preview.png", (0.6, 0.15, 0.1)),
            (build_mutton_skewer, "mutton-skewer", "mutton_skewer_preview.png", (0.6, 0.15, 0.1)),
            (build_kebab_skewer, "kebab-skewer", "kebab_skewer_preview.png", (0.6, 0.15, 0.1)),
            (build_sandwich, "tikka-sandwich", "sandwich_preview.png", (0.35, 0.13, 0.2)),
            (build_charcoal, "charcoal-bag", "charcoal_preview.png", (0.20, 0.21, 0.3))]:
        obj = checked_export(builder(), name, expected)
        assets.append((obj, image))
    print("Finished and validated all five GLB exports.", flush=True)
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--no-previews" in arguments:
        return
    for obj, _ in assets:
        obj.hide_render = True
    for obj, image in assets:
        obj.hide_render = False
        preview(obj, image)
        assert (PREVIEWS / image).is_file(), f"Missing preview: {image}"
        obj.hide_render = True
    for obj, _ in assets:
        obj.hide_render = False
    print("Finished all five 512 x 512 EEVEE previews.", flush=True)


if __name__ == "__main__":
    main()
