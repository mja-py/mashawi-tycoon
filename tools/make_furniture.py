"""Build five low-poly, texture-free seating/counter models with Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_furniture.py
Metres, Z up during modeling, +Y up in GLB, fronts face -Y (glTF/Godot +Z).
Origins are at the base centre of the bounding box.
make_props.py and make_icons_c.py import the shared helpers from here.
"""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_mashawi import box, lathe, material, mesh, metal, place, transform
from make_food import ROOT, TAU
from make_icons_a import beam, block, cylinder, glow, tube


OUTPUT = ROOT / "assets/models/furniture"


def glass(name, color, alpha=0.35):
    """Translucent glTF material (alphaMode BLEND)."""
    mat = material(name, color, 0.08)
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Alpha"].default_value = alpha
    for attr, value in (("surface_render_method", "BLENDED"),
                        ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, value)
        except (AttributeError, TypeError):
            pass
    return mat


def ball(name, radius, location, mat, subdivisions=1, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.location = location
    obj.data.materials.append(mat)
    return obj


def prism(name, contour, depth, mat, y=0.0):
    """Extrude an X/Z contour (counter-clockwise seen from -Y) along Y."""
    n = len(contour)
    front = [(x, y - depth / 2, z) for x, z in contour]
    back = [(x, y + depth / 2, z) for x, z in contour]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(j + n, (j + 1) % n + n, (j + 1) % n, j) for j in range(n)]
    obj = mesh(name, front + back, faces, [mat])
    # Normalise winding whatever the contour orientation.
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    return obj


def _join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        assert obj.type == "MESH", f"{name}: non-mesh part {obj.name}"
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def export_model(output, name, parts=None, groups=None, pivots=None,
                 max_tris=3000, width=None):
    """Join parts (or each named group) and export one GLB.

    groups: {object_name: parts} keeps several named nodes (e.g. a fan head);
    pivots: {object_name: (x, y, z)} puts that node's origin at the pivot
    (pre-centering coordinates) so it can rotate about it in Godot.
    """
    groups = groups or {name: parts}
    objects = [_join(group, key) for key, group in groups.items()]
    coords = [v.co.copy() for obj in objects for v in obj.data.vertices]
    offset = Vector(((min(c.x for c in coords) + max(c.x for c in coords)) / 2,
                     (min(c.y for c in coords) + max(c.y for c in coords)) / 2,
                     min(c.z for c in coords)))
    triangles = 0
    for obj in objects:
        pivot = Vector((pivots or {}).get(obj.name, offset)) - offset
        for vertex in obj.data.vertices:
            vertex.co -= offset + pivot
        obj.data.update()
        obj.location = pivot
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    bpy.context.view_layer.update()
    coords = [obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
    assert all(math.isfinite(c) for v in coords for c in v)
    assert 0 < triangles < max_tris, f"{name}: {triangles} triangles over budget"
    size = [max(c[i] for c in coords) - min(c[i] for c in coords) for i in range(3)]
    assert abs(min(c.z for c in coords)) < 1e-5, f"{name}: base off floor"
    for axis in (0, 1):
        assert abs(min(c[axis] for c in coords) + max(c[axis] for c in coords)) < 1e-5
    if width:
        assert width[0] <= size[0] <= width[1], f"{name}: width {size[0]:.3f}"
    materials = sorted({slot.material.name for obj in objects
                        for slot in obj.material_slots})
    print(f"{name}: {triangles} triangles; {size[0]:.3f} x {size[1]:.3f} x "
          f"{size[2]:.3f} m; materials {materials}", flush=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"),
                              export_format="GLB", export_apply=True,
                              export_yup=True, use_selection=True,
                              export_cameras=False, export_lights=False)
    # Hide so later exports/joins never pick these up.
    for obj in objects:
        obj.hide_set(True)
    return objects


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


# ---------------------------------------------------------------- builders

def chair(cx, facing, teak, cream, scale=1.0):
    """Simple chair at x=cx whose seat front points along +X*facing."""
    s = scale
    back_x = cx - facing * 0.066 * s
    parts = [block("Chair seat", (0.15 * s, 0.15 * s, 0.022 * s),
                   (cx, 0, 0.159 * s), cream, 0.004 * s)]
    for dx in (-0.06, 0.06):
        for dy in (-0.06, 0.06):
            parts.append(block("Chair leg", (0.016 * s, 0.016 * s, 0.148 * s),
                               (cx + dx * s, dy * s, 0.074 * s), teak))
    for dy in (-0.06, 0.06):
        parts.append(block("Chair back post", (0.018 * s, 0.018 * s, 0.15 * s),
                           (back_x, dy * s, 0.245 * s), teak))
    parts.append(block("Chair backrest", (0.016 * s, 0.13 * s, 0.07 * s),
                       (back_x, 0, 0.27 * s), cream, 0.004 * s))
    parts.append(block("Chair top rail", (0.022 * s, 0.15 * s, 0.016 * s),
                       (back_x, 0, 0.312 * s), teak, 0.003 * s))
    parts.append(block("Chair side rail", (0.13 * s, 0.012 * s, 0.012 * s),
                       (cx, -0.06 * s, 0.06 * s), teak))
    parts.append(block("Chair side rail", (0.13 * s, 0.012 * s, 0.012 * s),
                       (cx, 0.06 * s, 0.06 * s), teak))
    return parts


def round_table(radius, height, top_mat, base_mat, segments=20):
    top = lathe("Round table top", [(radius - 0.008, height - 0.022),
                                    (radius, height - 0.014),
                                    (radius, height - 0.004),
                                    (radius - 0.004, height)],
                [top_mat], segments=segments)
    return [top,
            cylinder("Table pedestal", 0.018, height - 0.03,
                     (0, 0, (height - 0.03) / 2 + 0.008), base_mat, segments=10),
            lathe("Table foot", [(0.085, 0), (0.085, 0.008), (0.05, 0.02),
                                 (0.02, 0.026)], [base_mat], segments=16)]


def build_table_set():
    teak = material("Furniture - teak", (0.36, 0.17, 0.065), 0.6)
    teak_top = material("Furniture - polished teak top", (0.47, 0.24, 0.09), 0.45)
    cream = material("Furniture - cream cushion", (0.93, 0.85, 0.68))
    parts = round_table(0.16, 0.27, teak_top, teak)
    parts += chair(-0.255, 1, teak, cream)
    parts += chair(0.255, -1, teak, cream)
    return parts


def build_chair():
    teak = bpy.data.materials.get("Furniture - teak") or material(
        "Furniture - teak", (0.36, 0.17, 0.065), 0.6)
    cream = bpy.data.materials.get("Furniture - cream cushion") or material(
        "Furniture - cream cushion", (0.93, 0.85, 0.68))
    return chair(0, 1, teak, cream)


def build_shopfront_counter():
    teak = material("Counter - teak front", (0.36, 0.17, 0.065), 0.6)
    trim = material("Counter - dark teak trim", (0.21, 0.095, 0.035), 0.6)
    cream = material("Counter - cream stone top", (0.93, 0.86, 0.71), 0.5)
    dark = material("Counter - charcoal till", (0.08, 0.09, 0.10), 0.5)
    pastry = material("Counter - golden pastries", (0.86, 0.55, 0.18))
    pane = glass("Counter - display glass", (0.75, 0.92, 0.95), 0.3)
    screen = glow("Counter - till screen", (0.2, 0.85, 0.7), 1.2)
    h, top_t = 0.5, 0.03
    body_h = h - top_t
    # Front run along X (y -0.21..-0.01) and a return leg at +X (x 0.5..0.7).
    parts = [block("Counter front run", (1.38, 0.19, body_h - 0.02),
                   (-0.01, -0.11, body_h / 2 + 0.01), teak),
             block("Counter return leg", (0.19, 0.24, body_h - 0.02),
                   (0.595, 0.10, body_h / 2 + 0.01), teak),
             block("Counter kick plinth", (1.36, 0.17, 0.02),
                   (-0.01, -0.105, 0.01), trim),
             block("Return kick plinth", (0.17, 0.25, 0.02),
                   (0.595, 0.095, 0.01), trim)]
    # Cream top split around the till recess (recess at x -0.05..0.17 not
    # needed: put it on the run next to the return leg).
    rx0, rx1, ry0, ry1 = 0.18, 0.42, -0.17, -0.04
    zt = body_h + top_t / 2
    parts += [block("Counter top left", (rx0 + 0.7, 0.21, top_t),
                    ((rx0 - 0.7) / 2, -0.105, zt), cream, 0.003),
              block("Counter top right", (0.7 - rx1, 0.21, top_t),
                    ((0.7 + rx1) / 2, -0.105, zt), cream, 0.003),
              block("Counter top front strip", (rx1 - rx0, ry0 + 0.21, top_t),
                    ((rx0 + rx1) / 2, (ry0 - 0.21) / 2, zt), cream),
              block("Counter top back strip", (rx1 - rx0, -ry1, top_t),
                    ((rx0 + rx1) / 2, ry1 / 2, zt), cream),
              block("Return top", (0.21, 0.215, top_t),
                    (0.595, 0.1075, zt), cream, 0.003)]
    parts.append(block("Till recess floor", (rx1 - rx0, ry1 - ry0, 0.01),
                       ((rx0 + rx1) / 2, (ry0 + ry1) / 2, body_h - 0.025), dark))
    till_x, till_y = (rx0 + rx1) / 2, (ry0 + ry1) / 2
    parts += [block("Till cash drawer", (0.16, 0.10, 0.035),
                    (till_x, till_y, body_h - 0.002), dark, 0.003),
              block("Till keypad", (0.09, 0.05, 0.018),
                    (till_x - 0.02, till_y - 0.015, body_h + 0.024), trim, 0.002)]
    screen_box = block("Till screen", (0.07, 0.008, 0.05),
                       (till_x + 0.04, till_y + 0.02, body_h + 0.06), screen,
                       rotation=(-0.35, 0, 0))
    parts += [screen_box,
              block("Till screen post", (0.012, 0.012, 0.05),
                    (till_x + 0.04, till_y + 0.025, body_h + 0.025), dark)]
    # Front decoration: dark teak panel frames with lighter insets.
    for i in range(5):
        x = -0.57 + i * 0.24
        parts.append(block("Counter front panel frame", (0.2, 0.006, 0.36),
                           (x, -0.208, 0.24), trim))
        parts.append(block("Counter front panel inset", (0.164, 0.008, 0.32),
                           (x, -0.21, 0.24), teak))
    parts.append(block("Counter front top band", (1.38, 0.008, 0.02),
                       (-0.01, -0.209, body_h - 0.012), trim))
    # Glass display box at the -X end with a teak base and pastries inside.
    dx, dy, z0 = -0.5, -0.105, h
    parts.append(block("Display base", (0.34, 0.19, 0.02), (dx, dy, z0 + 0.01),
                       trim, 0.003))
    parts.append(block("Display glass box", (0.33, 0.18, 0.15),
                       (dx, dy, z0 + 0.095), pane))
    parts.append(block("Display lid", (0.34, 0.19, 0.012), (dx, dy, z0 + 0.176),
                       trim, 0.002))
    for i in range(4):
        for j in range(2):
            parts.append(block("Pastry", (0.055, 0.045, 0.025),
                               (dx - 0.105 + i * 0.07, dy - 0.04 + j * 0.08,
                                z0 + 0.034), pastry, 0.008))
    return parts


def build_majlis_cushions():
    maroon = material("Majlis - maroon cushion", (0.38, 0.04, 0.07))
    gold = material("Majlis - gold cushion", (0.85, 0.60, 0.18))
    parts = []
    for i, x in enumerate((-0.195, 0, 0.195)):
        body, trim = (maroon, gold) if i != 1 else (gold, maroon)
        parts.append(block("Majlis cushion", (0.18, 0.18, 0.07),
                           (x, 0, 0.035), body, 0.02))
        parts.append(block("Cushion seam welt", (0.184, 0.184, 0.012),
                           (x, 0, 0.035), trim, 0.006))
        parts.append(cylinder("Cushion tufted button", 0.016, 0.012,
                              (x, 0, 0.071), trim, segments=8))
        for sx in (-1, 1):
            for sy in (-1, 1):
                parts.append(ball("Cushion corner tassel", 0.009,
                                  (x + sx * 0.088, sy * 0.088, 0.035), trim,
                                  subdivisions=1))
    return parts


def build_majlis_table():
    brass = metal("Majlis table - brass tray", (0.76, 0.52, 0.16))
    wood = material("Majlis table - dark carved wood", (0.20, 0.09, 0.035), 0.6)
    tray = lathe("Brass tray top", [(0.188, 0.104), (0.2, 0.108), (0.2, 0.12),
                                    (0.192, 0.12), (0.188, 0.112),
                                    (0.03, 0.111)], [brass], segments=24)
    parts = [tray,
             cylinder("Engraved centre boss", 0.06, 0.004, (0, 0, 0.113), brass,
                      segments=16)]
    # Octagonal folding stand: eight panels with arched cut-outs suggested by slats.
    for i in range(6):
        a = TAU * i / 6
        p = Vector((0.15 * math.cos(a), 0.15 * math.sin(a), 0))
        parts.append(beam("Carved table leg", p, p * 0.8 + Vector((0, 0, 0.104)),
                          0.022, wood, 0.016))
    for i in range(6):
        a0, a1 = TAU * i / 6, TAU * (i + 1) / 6
        for r, z in ((0.142, 0.04), (0.122, 0.098)):
            parts.append(beam("Leg stretcher", (r * math.cos(a0), r * math.sin(a0), z),
                              (r * math.cos(a1), r * math.sin(a1), z), 0.012, wood))
    return parts


def main():
    clear_scene()
    for name, builder in [("table-set", build_table_set), ("chair", build_chair),
                          ("shopfront-counter", build_shopfront_counter),
                          ("majlis-cushions", build_majlis_cushions),
                          ("majlis-table", build_majlis_table)]:
        export_model(OUTPUT, name, builder())
    print("Finished furniture exports.", flush=True)


if __name__ == "__main__":
    main()
