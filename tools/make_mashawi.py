"""Build five low-poly, texture-free Gulf BBQ assets with Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_mashawi.py
Metres, Z up during modeling, +Y up in GLB. All origins are at base centre.
Exports finish before 512 x 512 EEVEE previews start. Optional: -- --no-previews.
"""

import math
from pathlib import Path
import random
import sys

import bpy
from mathutils import Euler, Matrix, Vector

# Share the original food generator's flat materials and mesh conventions.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_food import (OUTPUT, PREVIEWS, TAU, lathe, lemon_wedge, material,
                       mesh, onion_ring, transform)


def metal(name, color=(0.56, 0.61, 0.65)):
    mat = material(name, color, 0.30)
    mat.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.8
    return mat


def place(parts, location, rotation=(0, 0, 0)):
    """Move a small ingredient assembly without parenting or extra nodes."""
    matrix = Matrix.Translation(Vector(location)) @ Euler(rotation).to_matrix().to_4x4()
    for obj in parts:
        obj.matrix_world = matrix @ obj.matrix_basis
    return parts


def box(name, dimensions, mat, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.name = name
    obj.scale = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("Single-step cut corners", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def rounded_rectangle(hx, hy, radius, steps=4):
    points = []
    for cx, cy, start in [(hx - radius, hy - radius, 0),
                           (-hx + radius, hy - radius, math.pi / 2),
                           (-hx + radius, -hy + radius, math.pi),
                           (hx - radius, -hy + radius, 3 * math.pi / 2)]:
        for i in range(steps + 1):
            angle = start + i * math.pi / (2 * steps)
            points.append((cx + radius * math.cos(angle),
                           cy + radius * math.sin(angle)))
    return points


def tray():
    steel = metal("Tray - brushed stainless")
    rim = metal("Tray - bright rolled rim", (0.75, 0.79, 0.82))
    # Continuous shallow shell: flat base, sloped walls, folded lip, inner floor.
    profile = [(0.221, 0.146, 0.020, 0), (0.228, 0.153, 0.024, 0.008),
               (0.250, 0.175, 0.035, 0.043),
               (0.250, 0.175, 0.035, 0.048),
               (0.240, 0.165, 0.029, 0.048),
               (0.216, 0.141, 0.020, 0.017)]
    vertices = [(x, y, z) for hx, hy, r, z in profile
                for x, y in rounded_rectangle(hx, hy, r)]
    n = 20
    faces, indices = [tuple(reversed(range(n)))], [0]
    for ring in range(len(profile) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((ring * n + i, ring * n + j,
                          (ring + 1) * n + j, (ring + 1) * n + i))
            indices.append(1 if ring in (2, 3) else 0)
    faces.append(tuple((len(profile) - 1) * n + i for i in range(n)))
    indices.append(0)
    return mesh("Shallow stainless preparation tray", vertices, faces,
                [steel, rim], indices)


def fleck(name, x, y, z, size, mat, rng):
    vertices = [(x - size, y - size * 0.45, z),
                (x + size * 0.75, y - size * 0.65, z + 0.0002),
                (x + size, y + size * 0.5, z),
                (x - size * 0.65, y + size * rng.uniform(0.5, 0.9), z)]
    return mesh(name, vertices, [(0, 1, 2, 3)], [mat])


def meat_cube(name, dimensions, colors, rng, speck=None, grilled=False):
    obj = box(name, dimensions, colors[0], min(dimensions) * 0.14)
    for mat in colors[1:]:
        obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.material_index = rng.randrange(len(colors))
    # Slightly irregular cut faces retain the chunky silhouette at icon scale.
    for vertex in obj.data.vertices:
        vertex.co.x += rng.uniform(-0.0015, 0.0015)
        vertex.co.y += rng.uniform(-0.0015, 0.0015)
    parts = [obj]
    sx, sy, sz = dimensions
    if speck:
        for i in range(3):
            parts.append(fleck(f"{name} fat or marinade {i + 1}",
                               rng.uniform(-0.25, 0.25) * sx,
                               rng.uniform(-0.25, 0.25) * sy,
                               sz / 2 + 0.0003, 0.0038, speck, rng))
        # A visible front-face fat fleck, in addition to the top marbling.
        parts.extend(place([fleck(f"{name} side fleck", 0, 0, 0,
                                   0.004, speck, rng)],
                           (sx * 0.12, -sy / 2 - 0.0004, 0.004),
                           (math.pi / 2, 0, 0)))
    if grilled:
        char = colors[-1]
        for i in (-1, 1):
            stripe = box(f"{name} seared stripe {i}",
                         (sx * 0.62, 0.004, 0.0007), char)
            parts.append(transform(stripe, (0, i * sy * 0.20, sz / 2 + 0.0005),
                                   (0, 0, -0.20)))
    return parts


def build_lamb_tray():
    colors = [material("Raw lamb - red pink", (0.57, 0.105, 0.15)),
              material("Raw lamb - rosy cut", (0.73, 0.22, 0.26)),
              material("Raw lamb - darker side", (0.42, 0.065, 0.09))]
    fat = material("Lamb - ivory fat", (0.95, 0.87, 0.78))
    return cube_tray(colors, fat, 153, "Lamb")


def build_chicken_tray():
    colors = [material("Tawook - pale pink orange", (0.92, 0.56, 0.35)),
              material("Tawook - golden marinade", (0.91, 0.43, 0.16)),
              material("Tawook - pale cut", (0.98, 0.70, 0.49))]
    marinade = material("Tawook - yellow yogurt marinade", (0.97, 0.69, 0.22))
    return cube_tray(colors, marinade, 227, "Chicken")


def cube_tray(colors, speck, seed, label):
    rng = random.Random(seed)
    parts = [tray()]
    for row in range(3):
        for col in range(4):
            size = (rng.uniform(0.077, 0.086), rng.uniform(0.072, 0.080),
                    rng.uniform(0.080, 0.090))
            rotation = (rng.uniform(-0.10, 0.10), rng.uniform(-0.10, 0.10),
                        rng.uniform(-0.17, 0.17))
            # Rest each rotated chunk on the inner floor, rather than floating.
            group = meat_cube(f"{label} cube {row * 4 + col + 1}", size,
                              colors, rng, speck)
            matrix = Euler(rotation).to_matrix()
            low = min((matrix @ vertex.co).z for vertex in group[0].data.vertices)
            parts.extend(place(group, ((col - 1.5) * 0.101 + rng.uniform(-0.003, 0.003),
                                        (row - 1) * 0.093, 0.0175 - low), rotation))
    return parts


def skewer(name, length, steel):
    # Flat rectangular blade with a short pointed tip; long axis is X.
    z, w = 0.0012, 0.004
    contour = [(-length / 2, -w), (length / 2 - 0.018, -w),
               (length / 2, 0), (length / 2 - 0.018, w), (-length / 2, w)]
    vertices = [(x, y, h) for h in (-z, z) for x, y in contour]
    faces = [tuple(reversed(range(5))), tuple(range(5, 10))]
    faces += [(i, (i + 1) % 5, (i + 1) % 5 + 5, i + 5) for i in range(5)]
    return mesh(name, vertices, faces, [steel])


def kofta(name, length, radius, colors, parsley, rng, grilled=False, height_ratio=1):
    # Seven faceted sections make a gently pinched, hand-formed minced-meat log.
    profile = [(-0.50, 0.55), (-0.44, 0.90), (-0.26, 1.02),
               (0, 0.94), (0.23, 1.03), (0.43, 0.91), (0.50, 0.50)]
    n = 8
    vertices = []
    for x, width in profile:
        for i in range(n):
            a = TAU * i / n
            r = radius * width * rng.uniform(0.96, 1.04)
            vertices.append((x * length, math.cos(a) * r,
                             math.sin(a) * r * height_ratio))
    faces = [tuple(reversed(range(n)))]
    for ring in range(len(profile) - 1):
        faces += [(ring * n + i, ring * n + (i + 1) % n,
                   (ring + 1) * n + (i + 1) % n, (ring + 1) * n + i)
                  for i in range(n)]
    faces.append(tuple((len(profile) - 1) * n + i for i in range(n)))
    obj = mesh(name, vertices, faces, colors,
               [rng.randrange(len(colors)) for _ in faces])
    parts = [obj]
    # Green pieces lie just above the broad, upper diagonal facets.
    for i in range(8):
        x = (i / 7 - 0.5) * length * 0.75
        side = -1 if i % 2 else 1
        group = [fleck(f"{name} parsley {i + 1}", 0, 0, 0,
                       0.0024 if grilled else 0.0031, parsley, rng)]
        parts.extend(place(group, (x, side * radius * 0.34,
                                   radius * 0.87 * height_ratio),
                           (-side * math.atan(height_ratio * math.tan(math.pi / 8)),
                            0, 0)))
    if grilled:
        for i in range(4):
            stripe = box(f"{name} char line {i}", (0.007, radius * 0.72, 0.001),
                         colors[-1])
            parts.append(transform(stripe, ((i - 1.5) * length / 5, 0, radius)))
    return parts


def build_kofta_tray():
    rng = random.Random(733)
    colors = [material("Raw kofta - brown red", (0.40, 0.16, 0.12)),
              material("Raw kofta - minced facets", (0.50, 0.22, 0.17)),
              material("Raw kofta - dark facets", (0.33, 0.12, 0.09))]
    parsley = material("Kofta - parsley specks", (0.13, 0.34, 0.065))
    steel = metal("Kofta - flat stainless skewers")
    parts = [tray()]
    for i in range(6):
        group = [skewer(f"Kofta flat skewer {i + 1}", 0.326, steel)]
        group += kofta(f"Raw kofta log {i + 1}", 0.242, 0.034,
                       colors, parsley, rng, height_ratio=1.35)
        parts.extend(place(group, ((i - 2.5) * 0.074, 0, 0.066),
                           (0, 0, math.pi / 2)))
    return parts


def oval(name, profile, mats, segments=24, ratio=2 / 3, wobble=0):
    obj = lathe(name, profile, mats, segments, wobble)
    obj.scale.y = ratio
    return obj


def chili(green, stem):
    # Bent tapered pepper, with a lifted stem at the thick end.
    centers = [(-0.062, 0.005, 0.010, 0.008), (-0.041, 0, 0.008, 0.012),
               (-0.010, -0.003, 0.006, 0.011),
               (0.023, 0.002, 0.007, 0.008), (0.049, 0.018, 0.012, 0.001)]
    vertices = [(x, y + r * math.cos(i * TAU / 6), z + r * math.sin(i * TAU / 6))
                for x, y, z, r in centers for i in range(6)]
    faces = [tuple(reversed(range(6)))]
    faces += [(j * 6 + i, j * 6 + (i + 1) % 6,
               (j + 1) * 6 + (i + 1) % 6, (j + 1) * 6 + i)
              for j in range(4) for i in range(6)]
    faces.append(tuple(range(24, 30)))
    pepper = mesh("Whole grilled green chili", vertices, faces, [green])
    stalk = box("Chili stem", (0.026, 0.004, 0.004), stem)
    transform(stalk, (-0.071, 0.005, 0.017), (0, 0.40, 0))
    return [pepper, stalk]


def build_platter():
    rng = random.Random(1609)
    ceramic = material("Platter - warm ivory ceramic", (0.91, 0.88, 0.79), 0.38)
    wheat = material("Regag - thin golden bread", (0.77, 0.55, 0.29))
    toast = material("Regag - toasted patches", (0.39, 0.22, 0.085))
    char = material("Grill - dark sear", (0.11, 0.055, 0.026))
    lamb = [material("Grilled lamb - mahogany", (0.35, 0.13, 0.065)),
            material("Grilled lamb - browned edges", (0.48, 0.23, 0.10)), char]
    chicken = [material("Grilled tawook - golden orange", (0.86, 0.42, 0.10)),
               material("Grilled tawook - golden cut", (0.97, 0.63, 0.23)), char]
    minced = [material("Grilled kofta - browned meat", (0.30, 0.17, 0.085)),
              material("Grilled kofta - warm facets", (0.42, 0.24, 0.12)), char]
    parsley = material("Grilled kofta - parsley", (0.16, 0.28, 0.055))
    steel = metal("Mixed grill - flat skewers")
    plate = oval("Oval mixed grill platter", [
        (0.19, 0), (0.25, 0.005), (0.295, 0.023), (0.300, 0.033),
        (0.288, 0.037), (0.245, 0.019), (0.17, 0.014)], [ceramic])
    parts = [plate]
    # Two paper-thin overlapping sheets, well below the raised ceramic rim.
    for i in range(2):
        bread = oval(f"Thin regag sheet {i + 1}",
                     [(0.13, 0), (0.242, 0.001), (0.246, 0.004), (0.16, 0.006)],
                     [wheat], segments=18, ratio=0.63, wobble=0.025)
        parts.append(transform(bread, ((i - 0.5) * 0.024, 0, 0.021 + i * 0.004),
                               (0, 0, (i - 0.5) * 0.19)))
    for i in range(15):
        a = i * 2.39996
        r = math.sqrt((i + 0.5) / 15) * 0.226
        parts.append(fleck(f"Regag toasted spot {i + 1}", r * math.cos(a),
                           r * math.sin(a) * 0.58, 0.032, rng.uniform(0.004, 0.012),
                           toast, rng))
    # Three cubed-meat skewers plus one long kofta, all readable from above.
    for row, (y, colors, label) in enumerate([
            (-0.080, lamb, "Lamb tikka A"), (-0.017, chicken, "Shish tawook"),
            (0.047, lamb, "Lamb tikka B")]):
        group = [skewer(f"{label} blade", 0.48, steel)]
        for i in range(4):
            chunks = meat_cube(f"{label} piece {i + 1}", (0.059, 0.048, 0.049),
                               colors[:2], rng)
            # Keep char restricted to narrow sear marks instead of entire faces.
            for stripe_index in (-1, 1):
                stripe = box(f"{label} sear {i} {stripe_index}",
                             (0.036, 0.004, 0.0008), char)
                chunks.append(transform(stripe, (0, stripe_index * 0.010, 0.025),
                                        (0, 0, -0.22)))
            group.extend(place(chunks, ((i - 1.5) * 0.071, 0, 0),
                               (0, 0, rng.uniform(-0.12, 0.12))))
        parts.extend(place(group, (-0.015, y, 0.060 + row * 0.004),
                           (0, 0, 0.045 - row * 0.05)))
    group = [skewer("Grilled kofta blade", 0.43, steel)]
    group += kofta("Long grilled kofta", 0.272, 0.026, minced, parsley, rng, True)
    # This fourth skewer rests across the others, giving the hero some height.
    parts.extend(place(group, (-0.018, 0.055, 0.110), (0, 0, -0.55)))

    red = material("Grilled tomato - red skin", (0.69, 0.075, 0.025))
    cut = material("Grilled tomato - juicy face", (0.89, 0.20, 0.065))
    tomato = lathe("Grilled tomato half", [(0.015, 0), (0.035, 0.009),
                    (0.042, 0.023), (0.043, 0.030)], [red, cut], segments=12)
    tomato.data.polygons[-1].material_index = 1
    parts.append(transform(tomato, (0.200, 0.038, 0.032)))
    for i in (-1, 1):
        stripe = box("Tomato grill mark", (0.054, 0.004, 0.0008), char)
        parts.append(transform(stripe, (0.200, 0.038 + i * 0.011, 0.0625),
                               (0, 0, -0.35)))
    green = material("Chili - deep green", (0.12, 0.29, 0.035))
    stem = material("Chili - stem", (0.24, 0.32, 0.055))
    parts.extend(place(chili(green, stem), (0.020, -0.142, 0.033), (0, 0, 0.13)))
    rind = material("Lemon - golden rind", (0.97, 0.68, 0.015))
    pith = material("Lemon - pale pith", (0.98, 0.91, 0.59))
    pulp = material("Lemon - yellow pulp", (0.99, 0.80, 0.16))
    # Upright wedge gives the hero a bright, raised focal garnish.
    parts.extend(place(lemon_wedge(rind, pith, pulp), (-0.177, -0.103, 0.037),
                       (0, 0, -0.28)))
    purple = material("Onion slices - purple edge", (0.52, 0.13, 0.37))
    white = material("Onion slices - ivory flesh", (0.94, 0.83, 0.88))
    for i in range(3):
        ring = onion_ring(f"Onion slice {i + 1}", purple, white)
        parts.append(transform(ring, (0.155 + i * 0.017, -0.090 + i * 0.013,
                                      0.040 + i * 0.006), (0.14, -0.10, i * 0.5)))
    return parts


def cup_handle(glass):
    # A small faceted C handle connects to the side of the waisted istikana.
    vertices, faces = [], []
    for i in range(13):
        a = -math.pi / 2 + math.pi * i / 12
        for j in range(6):
            b = TAU * j / 6
            r = 0.005
            vertices.append((0.052 + (0.031 + r * math.cos(b)) * math.cos(a),
                             r * math.sin(b),
                             0.137 + (0.052 + r * math.cos(b)) * math.sin(a)))
    faces.append(tuple(reversed(range(6))))
    for i in range(12):
        for j in range(6):
            faces.append((i * 6 + j, i * 6 + (j + 1) % 6,
                          (i + 1) * 6 + (j + 1) % 6, (i + 1) * 6 + j))
    faces.append(tuple(range(72, 78)))
    return mesh("Istikana - small glass C handle", vertices, faces, [glass])


def build_karak():
    ceramic = material("Karak saucer - warm white", (0.93, 0.89, 0.79), 0.35)
    gold = material("Karak saucer - honey rim", (0.70, 0.43, 0.14), 0.36)
    glass = material("Istikana - clear warm glass", (0.82, 0.91, 0.94), 0.12)
    shader = glass.node_tree.nodes["Principled BSDF"]
    shader.inputs["Alpha"].default_value = 0.26
    shader.inputs["Transmission Weight"].default_value = 0.18
    shader.inputs["IOR"].default_value = 1.46
    glass.diffuse_color = (0.82, 0.91, 0.94, 0.26)
    glass.surface_render_method = "DITHERED"
    tea = material("Karak - milky caramel tea", (0.61, 0.36, 0.16), 0.38)
    tea_top = material("Karak - creamy tea surface", (0.74, 0.49, 0.25), 0.32)
    saucer = lathe("Tiny tea saucer", [(0.050, 0), (0.085, 0.004),
                    (0.100, 0.014), (0.099, 0.020), (0.091, 0.020),
                    (0.065, 0.012), (0.038, 0.011)], [ceramic, gold], segments=20)
    # Narrow painted rim, still a flat Principled material without textures.
    for polygon in saucer.data.polygons[41:61]:
        polygon.material_index = 1
    cup = lathe("Waisted glass istikana", [
        (0.044, 0.012), (0.050, 0.018), (0.049, 0.030),
        (0.042, 0.090), (0.048, 0.160), (0.060, 0.226),
        (0.064, 0.247), (0.058, 0.247), (0.054, 0.226),
        (0.042, 0.160), (0.036, 0.090), (0.043, 0.032)], [glass], segments=20)
    drink = lathe("Milky karak filling", [(0.041, 0.032), (0.0345, 0.090),
                    (0.0405, 0.160), (0.051, 0.216), (0.0505, 0.218)],
                   [tea, tea_top], segments=20)
    drink.data.polygons[-1].material_index = 1
    return [saucer, cup, drink, cup_handle(glass)]


def export_asset(parts, name, expected):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        assert obj.type == "MESH", f"{name}: non-mesh part {obj.name}"
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.data.calc_loop_triangles()
    triangles = len(obj.data.loop_triangles)
    coordinates = [v.co for v in obj.data.vertices]
    assert all(math.isfinite(c) for vertex in coordinates for c in vertex)
    assert 0 < triangles < 2500, f"{name}: {triangles} triangles exceeds budget"
    assert abs(min(v.z for v in coordinates)) < 0.00001, f"{name}: base off floor"
    assert obj.location.length < 0.00001, f"{name}: origin is not base centre"
    for axis, nominal in enumerate(expected):
        assert nominal * 0.65 <= obj.dimensions[axis] <= nominal * 1.25, (
            f"{name}: unexpected dimensions {tuple(obj.dimensions)}")
    assert all(not node.type.startswith("TEX_") for slot in obj.material_slots
               for node in slot.material.node_tree.nodes), f"{name}: texture node found"
    print(f"{name}: {triangles} triangles; dimensions "
          f"{obj.dimensions.x:.3f} x {obj.dimensions.y:.3f} x {obj.dimensions.z:.3f} m",
          flush=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{name}.glb"),
                              export_format="GLB", export_apply=True,
                              export_yup=True, use_selection=True,
                              export_cameras=False, export_lights=False)
    return obj


def preview(obj, filename):
    """Same EEVEE studio setup as make_food, framing each asset to its size."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.75, 0.80, 0.87, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.view_settings.view_transform = "AgX"
    ground = material("Preview ground", (0.23, 0.28, 0.32))
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.001))
    plane = bpy.context.object
    plane.data.materials.append(ground)
    bpy.ops.object.light_add(type="SUN", location=(-3, -4, 6))
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(25), math.radians(-25), math.radians(-25))
    sun.data.energy = 2.4
    sun.data.angle = math.radians(12)
    bpy.ops.object.light_add(type="AREA", location=(0.5, -0.4, 1.0))
    fill = bpy.context.object
    fill.data.energy = 18
    fill.data.shape = "DISK"
    fill.data.size = 1.5
    target = Vector((0, 0, obj.dimensions.z * 0.43))
    fill.rotation_euler = (target - fill.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=(0.75, -1.05, 0.91))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(obj.dimensions) * 1.34
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = str(PREVIEWS / filename)
    bpy.ops.render.render(write_still=True)
    for helper in (plane, sun, fill, camera):
        bpy.data.objects.remove(helper, do_unlink=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    assets = []
    for builder, name, image, expected in [
            (build_lamb_tray, "lamb-tray", "lamb_preview.png", (0.5, 0.35, 0.12)),
            (build_chicken_tray, "chicken-tray", "chicken_preview.png", (0.5, 0.35, 0.12)),
            (build_kofta_tray, "kofta-tray", "kofta_preview.png", (0.5, 0.35, 0.12)),
            (build_platter, "mashawi-platter", "platter_preview.png", (0.6, 0.4, 0.15)),
            (build_karak, "karak-cup", "karak_preview.png", (0.2, 0.2, 0.25))]:
        obj = export_asset(builder(), name, expected)
        assets.append((obj, image))
    print("Finished all five GLB exports.", flush=True)
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--no-previews" not in arguments:
        for obj, _ in assets:
            obj.hide_render = True
        for obj, image in assets:
            obj.hide_render = False
            preview(obj, image)
            obj.hide_render = True
        for obj, _ in assets:
            obj.hide_render = False
        print("Finished all five 512 x 512 EEVEE previews.", flush=True)


if __name__ == "__main__":
    main()
