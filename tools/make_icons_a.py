"""Build nine low-poly, texture-free upgrade icons with Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_icons_a.py
Metres, Z up during modeling, +Y up in GLB. Origins are at base centre.
Exports finish before 512 x 512 EEVEE previews start. Optional: -- --no-previews.
"""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

# Reuse the BBQ generator's flat Principled materials and modeling/studio helpers.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_mashawi import (box, lathe, material, mesh, metal, place, preview,
                          transform)
from make_food import PREVIEWS, ROOT, TAU


OUTPUT = ROOT / "assets/models/icons"


def block(name, size, location, mat, bevel=0, rotation=(0, 0, 0)):
    return transform(box(name, size, mat, bevel), location, rotation)


def cylinder(name, radius, depth, location, mat, segments=12,
             rotation=(0, 0, 0)):
    return transform(lathe(name, [(radius, -depth / 2), (radius, depth / 2)],
                           [mat], segments=segments), location, rotation)


def beam(name, start, end, width, mat, depth=None):
    """Rectangular strut whose local Z axis follows the two endpoints."""
    a, b = Vector(start), Vector(end)
    obj = block(name, (width, depth or width, (b - a).length),
                (a + b) / 2, mat)
    obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return obj


def glow(name, color, strength=3):
    mat = material(name, color, 0.42)
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = strength
    return mat


def tube(name, points, radius, mat, sides=6):
    """Closed, flat-shaded polygon tube; no curves/modifiers left in the GLB."""
    points = [Vector(p) for p in points]
    vertices, faces = [], [tuple(reversed(range(sides)))]
    for i, point in enumerate(points):
        tangent = (points[min(i + 1, len(points) - 1)] -
                   points[max(0, i - 1)]).normalized()
        reference = Vector((0, -1, 0))
        if abs(tangent.dot(reference)) > 0.95:
            reference = Vector((1, 0, 0))
        u = tangent.cross(reference).normalized()
        v = tangent.cross(u).normalized()
        vertices.extend(tuple(point + radius * (math.cos(TAU * j / sides) * u +
                                                 math.sin(TAU * j / sides) * v))
                        for j in range(sides))
    for ring in range(len(points) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((ring * sides + j, ring * sides + k,
                          (ring + 1) * sides + k, (ring + 1) * sides + j))
    faces.append(tuple((len(points) - 1) * sides + j for j in range(sides)))
    return mesh(name, vertices, faces, [mat])


def flowing_tube(name, controls, mat, radius=0.006, steps=3):
    """Sample a short Catmull-Rom stroke in the sign's X/Z plane."""
    controls = [Vector((x, -0.041, z)) for x, z in controls]
    points = []
    for i in range(len(controls) - 1):
        a = controls[max(0, i - 1)]
        b, c = controls[i:i + 2]
        d = controls[min(i + 2, len(controls) - 1)]
        for step in range(steps):
            t = step / steps
            points.append(0.5 * ((2 * b) + (-a + c) * t +
                                 (2 * a - 5 * b + 4 * c - d) * t * t +
                                 (-a + 3 * b - 3 * c + d) * t * t * t))
    points.append(controls[-1])
    return tube(name, points, radius, mat)


def build_stand_big():
    red = material("Stand - tomato red", (0.69, 0.055, 0.045))
    cream = material("Stand - canvas cream", (0.96, 0.85, 0.61))
    wood = material("Stand - warm timber", (0.38, 0.20, 0.085))
    parts = [block("Wide red counter", (0.434, 0.244, 0.205),
                   (0, 0, 0.1025), red, 0.005),
             block("Cream counter lip", (0.454, 0.264, 0.019),
                   (0, 0, 0.2145), cream, 0.003)]
    for x in (-0.202, 0.202):
        for y in (-0.102, 0.102):
            parts.append(block("Four timber canopy posts", (0.018, 0.018, 0.408),
                               (x, y, 0.204), wood))
    # Adjacent solid gable strips form a continuous striped pitched canopy.
    for i in range(10):
        x0, x1 = -0.24 + i * 0.048, -0.24 + (i + 1) * 0.048
        contour = [(-0.155, 0.391), (0, 0.467), (0.155, 0.391),
                   (0.155, 0.383), (0, 0.459), (-0.155, 0.383)]
        vertices = [(x, y, z) for x in (x0, x1) for y, z in contour]
        # The Y/Z gable contour is clockwise; wind the extrusion outwards.
        faces = [tuple(range(6)), tuple(reversed(range(6, 12)))]
        faces += [(j + 6, (j + 1) % 6 + 6, (j + 1) % 6, j) for j in range(6)]
        mat = red if i % 2 == 0 else cream
        parts.append(mesh(f"Striped roof panel {i + 1}", vertices, faces, [mat]))
        parts.append(block(f"Front canvas valance {i + 1}", (0.048, 0.009, 0.033),
                           ((x0 + x1) / 2, -0.153, 0.373), mat))
    for x in (-0.15, -0.075, 0, 0.075, 0.15):
        parts.append(block("Counter cream inset slat", (0.027, 0.003, 0.136),
                           (x, -0.123, 0.105), cream))
    return parts


def build_grill_double():
    iron = material("Double grill - charcoal enamel", (0.065, 0.075, 0.085))
    steel = metal("Double grill - steel rims", (0.40, 0.44, 0.47))
    ember = glow("Double grill - glowing orange coals", (1.0, 0.16, 0.012), 2.5)
    ash = material("Double grill - black charcoal", (0.09, 0.055, 0.035))
    meat = material("Double grill - golden kebab", (0.72, 0.26, 0.055))
    handle = material("Double grill - wooden grips", (0.34, 0.14, 0.04))
    parts = []
    for unit, x in enumerate((-0.123, 0.123)):
        parts.append(block("Grill firebox floor", (0.226, 0.205, 0.025),
                           (x, 0, 0.1395), iron))
        for side in (-1, 1):
            parts.append(block("Grill front/back wall", (0.226, 0.013, 0.075),
                               (x, side * 0.103, 0.1775), iron))
            parts.append(block("Grill side wall", (0.013, 0.205, 0.075),
                               (x + side * 0.1065, 0, 0.1775), iron))
            parts.append(block("Steel skewer rest", (0.226, 0.016, 0.008),
                               (x, side * 0.103, 0.219), steel))
            for y in (-0.078, 0.078):
                parts.append(block("Short grill leg", (0.021, 0.021, 0.13),
                                   (x + side * 0.085, y, 0.065), iron))
        for i in range(8):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.029)
            coal = bpy.context.object
            coal.name = f"Glowing coal {unit + 1}-{i + 1}"
            coal.scale = (1, 0.8, 0.55)
            coal.location = (x + (i % 4 - 1.5) * 0.047,
                             (i // 4 - 0.5) * 0.078, 0.174)
            coal.data.materials.append(ember)
            coal.data.materials.append(ash)
            for polygon in coal.data.polygons:
                polygon.material_index = int(polygon.index % 4 == 0)
            parts.append(coal)
    # Three long skewers bridge both fireboxes, visibly demonstrating the upgrade.
    for i in range(3):
        y = (i - 1) * 0.073
        parts.append(block("Long steel skewer", (0.465, 0.006, 0.006),
                           (-0.005, y, 0.237), steel))
        parts.append(block("Skewer wooden grip", (0.042, 0.015, 0.014),
                           (-0.218, y, 0.237), handle, 0.002))
        for x in (-0.15, -0.075, 0.075, 0.15):
            parts.append(block("Kebab chunk", (0.043, 0.035, 0.031),
                               (x, y, 0.239), meat, 0.003))
    return parts


def build_fridge():
    white = material("Fridge - porcelain white", (0.89, 0.93, 0.93))
    trim = material("Fridge - door gasket", (0.20, 0.25, 0.28))
    steel = metal("Fridge - stainless handle")
    blue = glow("Fridge - blue status light", (0.015, 0.38, 1.0), 2)
    parts = [block("Upright refrigerator cabinet", (0.414, 0.29, 0.60),
                   (0, 0.014, 0.32), white, 0.008),
             block("Refrigerator door gasket", (0.399, 0.014, 0.563),
                   (0, -0.139, 0.323), trim, 0.004),
             block("White fridge door", (0.388, 0.024, 0.55),
                   (0, -0.153, 0.323), white, 0.006),
             block("Steel vertical door handle", (0.016, 0.018, 0.186),
                   (-0.133, -0.188, 0.353), steel, 0.003),
             block("Small blue indicator", (0.025, 0.006, 0.012),
                   (0.125, -0.168, 0.543), blue, 0.002)]
    for z in (0.277, 0.429):
        parts.append(block("Handle bracket", (0.016, 0.027, 0.012),
                           (-0.133, -0.174, z), steel))
    for x in (-0.155, 0.155):
        for y in (-0.09, 0.105):
            parts.append(block("Fridge foot", (0.035, 0.035, 0.03),
                               (x, y, 0.015), trim))
    return parts


def build_cooler():
    white = material("Cooler - insulated white panels", (0.87, 0.92, 0.93))
    grey = material("Cooler - grey cold room door", (0.39, 0.47, 0.52))
    trim = metal("Cooler - frame and latch", (0.62, 0.69, 0.73))
    ice = material("Cooler - icy snowflake", (0.43, 0.83, 0.98))
    parts = [block("Walk-in cooler enclosure", (0.48, 0.34, 0.395),
                   (0, 0, 0.1975), white, 0.006),
             block("Cold room door frame", (0.268, 0.018, 0.351),
                   (-0.05, -0.177, 0.1825), trim, 0.004),
             block("Heavy grey cooler door", (0.244, 0.02, 0.326),
                   (-0.05, -0.193, 0.183), grey, 0.003),
             block("Cooler lever latch", (0.05, 0.021, 0.012),
                   (-0.125, -0.218, 0.16), trim, 0.002)]
    for z in (0.086, 0.28):
        parts.append(block("Door hinge", (0.028, 0.016, 0.036),
                           (0.073, -0.209, z), trim, 0.002))
    # Six radial spokes, each with two short crystalline branches.
    center = Vector((-0.035, -0.209, 0.252))
    for i in range(6):
        a = TAU * i / 6
        direction = Vector((math.cos(a), 0, math.sin(a)))
        parts.append(beam("Snowflake spoke", center, center + direction * 0.053,
                          0.007, ice, 0.004))
        for side in (-1, 1):
            branch = Vector((math.cos(a + side * 0.75), 0,
                             math.sin(a + side * 0.75)))
            start = center + direction * 0.031
            parts.append(beam("Snowflake crystal branch", start,
                              start + branch * 0.018, 0.005, ice, 0.004))
    for x in (-0.208, 0.174):
        parts.append(block("Insulated panel seam", (0.003, 0.002, 0.362),
                           (x, -0.171, 0.199), trim))
    return parts


def build_shade_sail():
    canvas = material("Shade sail - cream canvas", (0.95, 0.85, 0.63))
    edge = material("Shade sail - stitched border", (0.71, 0.55, 0.30))
    wood = material("Shade sail - timber poles", (0.38, 0.23, 0.11))
    steel = metal("Shade sail - pole shoes", (0.39, 0.43, 0.44))
    corners = [(-0.221, -0.15, 0.384), (0.221, -0.15, 0.45),
               (0.025, 0.225, 0.417)]
    # A gently dipped triangular membrane with actual thickness and a closed edge.
    top = corners + [(0.008, -0.008, 0.367)]
    vertices = top + [(x, y, z - 0.004) for x, y, z in top]
    faces = [(0, 1, 3), (1, 2, 3), (2, 0, 3),
             (7, 5, 4), (7, 6, 5), (7, 4, 6),
             (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 4, 0)]
    parts = [mesh("Triangular stretched cream sail", vertices, faces, [canvas])]
    for i, (x, y, z) in enumerate(corners):
        parts.append(cylinder("Sail timber pole", 0.011, z + 0.014,
                              (x, y, (z + 0.014) / 2), wood, segments=8))
        parts.append(cylinder("Sail pole footing", 0.019, 0.012,
                              (x, y, 0.006), steel, segments=8))
        parts.append(tube("Reinforced sail edge", [corners[i], corners[(i + 1) % 3]],
                          0.0035, edge))
    return parts


def build_speaker():
    black = material("Speaker - black cabinet", (0.022, 0.028, 0.037))
    rim = material("Speaker - graphite driver rims", (0.13, 0.16, 0.19))
    cone = material("Speaker - charcoal cones", (0.045, 0.055, 0.069))
    cap = metal("Speaker - driver dust caps", (0.29, 0.34, 0.38))
    note = material("Speaker - floating gold musical note", (1.0, 0.61, 0.08))
    parts = [block("Black speaker enclosure", (0.40, 0.225, 0.415),
                   (0, 0, 0.2075), black, 0.009)]
    for z, radius in ((0.129, 0.088), (0.309, 0.065)):
        driver = lathe("Round faceted speaker driver",
                       [(radius, 0), (radius, 0.009), (radius * 0.83, 0.015),
                        (radius * 0.40, 0.004), (radius * 0.31, 0.018)],
                       [rim, cone, cap], segments=16)
        for polygon in driver.data.polygons:
            polygon.material_index = (0 if polygon.index <= 16 else
                                      2 if polygon.index > 48 else 1)
        parts.append(transform(driver, (0, -0.114, z), (math.pi / 2, 0, 0)))
    # A single eighth note, made entirely of solid mesh shapes above the cabinet.
    head = cylinder("Musical note oval head", 0.033, 0.018,
                    (-0.025, -0.01, 0.479), note, rotation=(math.pi / 2, 0, 0))
    head.scale.x = 1.30
    parts.append(head)
    parts.append(beam("Musical note stem", (0.012, -0.01, 0.48),
                      (0.012, -0.01, 0.613), 0.012, note, 0.018))
    parts.append(tube("Musical note curved flag", [(0.013, -0.01, 0.609),
                      (0.049, -0.01, 0.588), (0.065, -0.01, 0.565),
                      (0.051, -0.01, 0.544)], 0.011, note))
    return parts


def build_neon_sign():
    board = material("Neon - midnight signboard", (0.024, 0.035, 0.065))
    frame = metal("Neon - dark metal frame", (0.15, 0.19, 0.26))
    pink = glow("Neon - glowing magenta tubes", (1.0, 0.015, 0.36), 4)
    parts = [block("Dark neon signboard", (0.466, 0.044, 0.277),
                   (0, 0, 0.2195), board, 0.006)]
    for z in (0.079, 0.36):
        parts.append(block("Sign frame horizontal", (0.48, 0.052, 0.012),
                           (0, 0, z), frame, 0.002))
    for x in (-0.234, 0.234):
        parts.append(block("Sign frame vertical", (0.012, 0.052, 0.281),
                           (x, 0, 0.2195), frame))
    for x in (-0.147, 0.147):
        parts.append(block("Sign support", (0.015, 0.018, 0.08),
                           (x, 0, 0.04), frame))
        parts.append(block("Sign foot", (0.081, 0.103, 0.012),
                           (x, 0, 0.006), frame, 0.002))
    # Decorative Arabic-like connected strokes, deliberately no font or real text.
    parts.append(flowing_tube("Neon flowing connected squiggle", [
        (-0.19, 0.211), (-0.17, 0.174), (-0.13, 0.184), (-0.118, 0.237),
        (-0.096, 0.201), (-0.068, 0.235), (-0.044, 0.2), (-0.005, 0.228),
        (0.034, 0.202), (0.065, 0.229), (0.096, 0.204), (0.144, 0.22),
        (0.177, 0.266), (0.169, 0.303)], pink))
    parts.append(flowing_tube("Neon lower swooping stroke", [
        (-0.061, 0.167), (-0.025, 0.143), (0.039, 0.144),
        (0.093, 0.163), (0.122, 0.186)], pink, radius=0.005))
    for x, z in ((-0.098, 0.274), (-0.068, 0.277), (0.041, 0.271)):
        parts.append(cylinder("Neon small floating dot", 0.008, 0.009,
                              (x, -0.041, z), pink, segments=8,
                              rotation=(math.pi / 2, 0, 0)))
    return parts


def build_majlis():
    red = material("Majlis - deep red rug", (0.38, 0.035, 0.06))
    gold = material("Majlis - woven gold border", (0.80, 0.54, 0.17))
    cushion = material("Majlis - ruby cushions", (0.64, 0.075, 0.105))
    piping = material("Majlis - cushion gold seam", (0.94, 0.70, 0.29))
    brass = metal("Majlis - brass tray table", (0.72, 0.47, 0.13))
    parts = [block("Floor rug gold border", (0.48, 0.376, 0.008),
                   (0, 0, 0.004), gold),
             block("Deep red rug field", (0.45, 0.346, 0.002),
                   (0, 0, 0.009), red)]
    for i, (x, y, angle) in enumerate(((-0.147, 0.099, -0.10),
                                      (0, 0.109, 0), (0.147, 0.099, 0.10))):
        group = [block("Cushion lower welt", (0.129, 0.103, 0.017),
                       (0, 0, 0.0085), piping, 0.006),
                 block("Plump low majlis cushion", (0.127, 0.101, 0.051),
                       (0, 0, 0.0285), cushion, 0.015),
                 block("Cushion woven stripe", (0.018, 0.073, 0.001),
                       (0, 0, 0.0545), gold)]
        parts.extend(place(group, (x, y, 0.010), (0, 0, angle)))
    table = lathe("Small round brass tray tabletop", [
        (0.071, 0.078), (0.081, 0.083), (0.083, 0.094),
        (0.077, 0.096), (0.073, 0.088), (0.061, 0.087)], [brass], segments=16)
    parts.append(transform(table, (0, -0.066, 0)))
    for i in range(3):
        a = TAU * i / 3
        parts.append(beam("Brass tray table leg", (0.057 * math.cos(a),
                          -0.066 + 0.057 * math.sin(a), 0.011),
                          (0.046 * math.cos(a), -0.066 + 0.046 * math.sin(a), 0.081),
                          0.009, brass))
    # Sparse woven diamonds, solid geometry rather than an image texture.
    for x in (-0.183, 0.183):
        parts.append(block("Rug gold diamond", (0.022, 0.022, 0.001),
                           (x, -0.10, 0.0105), gold, rotation=(0, 0, math.pi / 4)))
    return parts


def build_helper():
    wood = material("Helper - warm wooden hat stand", (0.39, 0.21, 0.085))
    lightwood = material("Helper - wood top surface", (0.60, 0.36, 0.15))
    white = material("Helper - white chef toque", (0.97, 0.95, 0.87))
    seam = material("Helper - toque band pleats", (0.77, 0.79, 0.76))
    steel = metal("Helper - spatula stainless steel", (0.66, 0.72, 0.75))
    grip = material("Helper - spatula red grip", (0.61, 0.055, 0.035))
    parts = [block("Wooden stand base", (0.414, 0.245, 0.023),
                   (0, 0, 0.0115), wood, 0.005),
             cylinder("Hat stand spindle", 0.025, 0.19,
                      (-0.04, 0.018, 0.118), wood),
             cylinder("Hat stand top disc", 0.094, 0.018,
                      (-0.04, 0.018, 0.215), lightwood, segments=16)]
    band = lathe("Tall chef toque band", [(0.108, 0.222), (0.11, 0.23),
                 (0.105, 0.312), (0.118, 0.338)], [white], segments=16)
    parts.append(transform(band, (-0.04, 0.018, 0)))
    # Five angular puffs give the recognizable tall chef-hat crown.
    for i in range(5):
        a = TAU * i / 5
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
        puff = bpy.context.object
        puff.name = "Faceted chef toque crown puff"
        puff.scale = (0.078, 0.078, 0.079)
        puff.location = (-0.04 + 0.066 * math.cos(a),
                         0.018 + 0.066 * math.sin(a), 0.356 + 0.009 * (i % 2))
        puff.data.materials.append(white)
        parts.append(puff)
    for i in range(7):
        a = math.pi + (i + 1) * math.pi / 8
        parts.append(beam("Toque vertical stitched pleat",
                          (-0.04 + 0.108 * math.cos(a),
                           0.018 + 0.108 * math.sin(a), 0.24),
                          (-0.04 + 0.105 * math.cos(a),
                           0.018 + 0.105 * math.sin(a), 0.302), 0.002, seam))
    # A leaning slotted spatula: rails leave three real open slots in the blade.
    spatula = [block("Spatula red handle", (0.026, 0.018, 0.135),
                     (0, 0, 0.0675), grip, 0.004),
               block("Spatula steel neck", (0.015, 0.009, 0.075),
                     (0, 0, 0.17), steel),
               block("Spatula blade heel", (0.079, 0.009, 0.018),
                     (0, 0, 0.208), steel, 0.002),
               block("Spatula blade top", (0.079, 0.009, 0.012),
                     (0, 0, 0.279), steel, 0.002)]
    for x in (-0.0345, -0.0115, 0.0115, 0.0345):
        spatula.append(block("Spatula slotted blade rail", (0.010, 0.009, 0.059),
                             (x, 0, 0.2455), steel))
    parts.extend(place(spatula, (0.106, -0.092, 0.033), (0, 0.29, -0.12)))
    return parts


def export_asset(parts, name):
    """Same GLB conventions as make_mashawi, with the tighter icon budget."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        assert obj.type == "MESH", f"{name}: non-mesh part {obj.name}"
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Centre the complete footprint, including handles/feet, on the base origin.
    coordinates = [v.co.copy() for v in obj.data.vertices]
    offset = Vector(((min(v.x for v in coordinates) + max(v.x for v in coordinates)) / 2,
                     (min(v.y for v in coordinates) + max(v.y for v in coordinates)) / 2,
                     min(v.z for v in coordinates)))
    for vertex in obj.data.vertices:
        vertex.co -= offset
    obj.data.update()
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.data.calc_loop_triangles()
    triangles = len(obj.data.loop_triangles)
    coordinates = [v.co for v in obj.data.vertices]
    assert all(math.isfinite(c) for vertex in coordinates for c in vertex)
    assert 0 < triangles < 1500, f"{name}: {triangles} triangles exceeds icon budget"
    width = max(v.x for v in coordinates) - min(v.x for v in coordinates)
    assert 0.399 <= width <= 0.501, f"{name}: width {width:.4f} outside icon range"
    assert abs(min(v.z for v in coordinates)) < 0.00001, f"{name}: base off floor"
    assert obj.location.length < 0.00001, f"{name}: origin is not base centre"
    for axis in (0, 1):
        assert abs(min(v[axis] for v in coordinates) +
                   max(v[axis] for v in coordinates)) < 0.00001
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


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    assets = []
    for name, builder in [
            ("stand-big", build_stand_big), ("grill-double", build_grill_double),
            ("fridge", build_fridge), ("cooler", build_cooler),
            ("shade-sail", build_shade_sail), ("speaker", build_speaker),
            ("neon-sign", build_neon_sign), ("majlis", build_majlis),
            ("helper", build_helper)]:
        assets.append((export_asset(builder(), name), name))
    print("Finished all nine upgrade icon GLB exports.", flush=True)
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--no-previews" not in arguments:
        for obj, _ in assets:
            obj.hide_render = True
        for obj, name in assets:
            obj.hide_render = False
            # Absolute path uses the shared 512 x 512 EEVEE studio unchanged.
            preview(obj, str(PREVIEWS / f"icon_{name}_preview.png"))
            obj.hide_render = True
        for obj, _ in assets:
            obj.hide_render = False
        print("Finished all nine 512 x 512 EEVEE icon previews.", flush=True)


if __name__ == "__main__":
    main()
