"""Build five low-poly, texture-free Promote icons with Blender 5.2.

Run from the project root:
    /opt/homebrew/bin/blender -b -P tools/make_promo_icons.py

Metres, Z up while modeling, +Y up in GLB; fronts face -Y (Godot +Z).
Origins are at the bounding-box base centre, using the dallah exporter.
Only writes promo-{samples,chat,maps,blogger,video}.glb in assets/models/icons/.
No .blend, previews, textures, external resources, or bytecode are written.
The tasting tray intentionally keeps natural, lower cocktail-pick proportions.
Requires the same transitive helper modules as make_icon_dallah.py, including
make_mashawi.py and make_food.py from the full project.
"""

import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Matrix

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_furniture import (beam, block, cylinder, export_model, lathe,
                            material, mesh, metal, tube)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/models/icons"
TAU = math.tau


def palette():
    """Create once; every icon uses a subset of these seven shared materials."""
    return {
        "cream": material("Promo - cream", (0.95, 0.88, 0.73), 0.8),
        "sand": material("Promo - kraft sand", (0.72, 0.55, 0.33), 0.8),
        "clay": material("Promo - clay red", (0.68, 0.23, 0.15), 0.8),
        "palm": material("Promo - palm green", (0.19, 0.36, 0.22), 0.8),
        "gold": metal("Promo - warm brass", (0.78, 0.53, 0.19)),
        "dark": material("Promo - charcoal", (0.065, 0.073, 0.065), 0.8),
        "brown": material("Promo - grilled brown", (0.30, 0.125, 0.055), 0.8),
    }


def rounded_rectangle(width, height, radius, steps=2):
    """CCW X/Z contour, three vertices per corner at the default resolution."""
    points = []
    for cx, cz, start in ((width / 2 - radius, -height / 2 + radius, -math.pi / 2),
                          (width / 2 - radius, height / 2 - radius, 0),
                          (-width / 2 + radius, height / 2 - radius, math.pi / 2),
                          (-width / 2 + radius, -height / 2 + radius, math.pi)):
        for i in range(steps + 1):
            angle = start + i * math.pi / (2 * steps)
            points.append((cx + radius * math.cos(angle),
                           cz + radius * math.sin(angle)))
    return points


def extrude(name, contour, depth, mat, location=(0, 0, 0)):
    """Closed X/Z silhouette extruded along Y; caps are triangulated in QA."""
    n = len(contour)
    vertices = [(x, y, z) for y in (-depth / 2, depth / 2)
                for x, z in contour]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    obj = mesh(name, vertices, faces, [mat])
    obj.location = location
    return obj


def rounded_plate(name, width, height, radius, depth, mat, location):
    return extrude(name, rounded_rectangle(width, height, radius), depth,
                   mat, location)


def pierced_plate(name, contour, hole, radius, depth, mat, location,
                  lining=None, border=0.0, segments=12):
    """Convex plate with a real through-hole, optionally cream-lined.

    Cast rays from the hole centre to the convex perimeter. Include both
    regular hole samples and every outer corner, so no silhouette is lost.
    Front/back strips and the hole wall form one closed mesh without booleans.
    """
    hx, hz = hole
    angles = {round(TAU * i / segments, 10) for i in range(segments)}
    angles.update(round(math.atan2(z - hz, x - hx) % TAU, 10)
                  for x, z in contour)
    outer, inner, rim = [], [], []
    for angle in sorted(angles):
        dx, dz = math.cos(angle), math.sin(angle)
        hits = []
        for i, (ax, az) in enumerate(contour):
            bx, bz = contour[(i + 1) % len(contour)]
            sx, sz = bx - ax, bz - az
            determinant = dx * sz - dz * sx
            if abs(determinant) < 1e-12:
                continue
            t = ((ax - hx) * sz - (az - hz) * sx) / determinant
            u = ((ax - hx) * dz - (az - hz) * dx) / determinant
            if t > 0 and -1e-8 <= u <= 1 + 1e-8:
                hits.append(t)
        assert hits, f"{name}: hole outside contour"
        distance = min(hits)
        assert distance > radius + border, f"{name}: hole crosses perimeter"
        outer.append((hx + distance * dx, hz + distance * dz))
        inner.append((hx + radius * dx, hz + radius * dz))
        rim.append((hx + (radius + border) * dx,
                    hz + (radius + border) * dz))
    n = len(outer)
    # Each contour has a front and back loop.
    loops = [outer, rim, inner] if lining else [outer, inner]
    vertices = [(x, y, z) for loop in loops
                for y in (-depth / 2, depth / 2) for x, z in loop]
    faces, indices = [], []

    def strip(a, b, material_index):
        for i in range(n):
            j = (i + 1) % n
            faces.append((a * n + i, a * n + j, b * n + j, b * n + i))
            indices.append(material_index)

    strip(0, 1, 0)  # Outer wall.
    strip(0, 2, 0)  # Front face.
    strip(1, 3, 0)  # Back face.
    if lining:
        strip(2, 4, 1)
        strip(3, 5, 1)
        strip(4, 5, 1)  # Cream inner wall, with empty space through it.
    else:
        strip(2, 3, 0)
    obj = mesh(name, vertices, faces, [mat, lining] if lining else [mat])
    for polygon, index in zip(obj.data.polygons, indices):
        polygon.material_index = index
    obj.location = location
    return obj


def build_samples(p):
    parts = [block("Small folded cloth lower leaf", (0.400, 0.250, 0.012),
                   (0, 0, 0.006), p["cream"]),
             block("Small folded cloth upper leaf", (0.292, 0.222, 0.010),
                   (0.018, 0.007, 0.016), p["sand"]),
             lathe("Small round brass tasting tray",
                   [(0.112, 0.018), (0.123, 0.024), (0.123, 0.046),
                    (0.113, 0.046), (0.107, 0.033), (0.012, 0.033)],
                   [p["gold"]], segments=20)]
    # Only five tiny bites, not rows of food or full-length meal skewers.
    # Rear picks are taller so they remain separate from the foreground ones.
    bites = [(-0.055, 0.042, 0.210), (0.022, 0.053, 0.220),
             (-0.065, -0.031, 0.182), (0.004, -0.040, 0.193),
             (0.065, -0.004, 0.204)]
    for i, (x, y, height) in enumerate(bites, 1):
        parts.append(block(f"Taster {i} browned meat cube", (0.044, 0.041, 0.040),
                           (x, y, 0.052), p["brown"],
                           rotation=(0, 0, 0.11 if i % 2 else -0.12)))
        parts.append(block(f"Taster {i} green pepper square", (0.046, 0.043, 0.014),
                           (x, y, 0.078), p["palm"],
                           rotation=(0, 0, -0.08 if i % 2 else 0.09)))
        parts.append(tube(f"Taster {i} upright cocktail pick",
                          [(x, y, 0.050), (x, y, height)],
                          0.007, p["sand"], sides=6))
    # 14 mm diameter, resting at the front of the tray, clear of the cubes.
    parts.append(tube("One loose cocktail pick on tray",
                      [(-0.050, -0.084, 0.040), (0.061, -0.076, 0.040)],
                      0.007, p["sand"], sides=6))
    return parts


def speech_bubble(name, width, height, x, z, right_tail, mat):
    contour = rounded_rectangle(width, height, 0.018)
    bottom = -height / 2
    contour += ([(0.028, bottom), (0.078, bottom - 0.026), (0.065, bottom)]
                if right_tail else
                [(-0.065, bottom), (-0.078, bottom - 0.026), (-0.028, bottom)])
    return extrude(name, contour, 0.028, mat, (x, -0.013, z))


def build_chat(p):
    # The tiny rear kickstand is structural; the front silhouette is a phone.
    parts = [rounded_plate("Regulars upright smartphone", 0.285, 0.540, 0.024,
                           0.052, p["dark"], (-0.050, 0.035, 0.270)),
             rounded_plate("Regulars cream screen", 0.247, 0.486, 0.014,
                           0.012, p["cream"], (-0.050, 0.006, 0.270)),
             beam("Regulars rear kickstand", (-0.050, 0.155, 0.012),
                  (-0.050, 0.055, 0.240), 0.018, p["dark"]),
             block("Regulars rear kickstand foot", (0.150, 0.028, 0.016),
                   (-0.050, 0.155, 0.008), p["dark"])]
    for name, x, z, width, right, colour in (
            ("Upper clay offer bubble", -0.066, 0.386, 0.215, False, "clay"),
            ("Lower palm offer bubble", -0.028, 0.191, 0.205, True, "palm")):
        parts.append(speech_bubble(name, width, 0.130, x, z, right, p[colour]))
        for i, dx in enumerate((-0.047, 0, 0.047), 1):
            parts.append(cylinder(f"{name} cream dot {i}", 0.012, 0.008,
                                  (x + dx, -0.030, z), p["cream"], segments=8,
                                  rotation=(math.pi / 2, 0, 0)))
    tag = pierced_plate("Tiny leaning gold price tag",
                        [(-0.055, -0.060), (0.055, -0.060), (0.055, 0.025),
                         (0.018, 0.060), (-0.018, 0.060), (-0.055, 0.025)],
                        (0, 0.032), 0.012, 0.018, p["gold"],
                        (0.140, -0.008, 0.070))
    tag.rotation_euler = (-0.58, -0.28, 0)
    parts.append(tag)
    return parts


# The map's fold runs across X; all overlays share exactly the same slopes.
MAP_X = (-0.200, -1 / 15, 1 / 15, 0.200)
MAP_Z = (0.014, 0.034, 0.014, 0.034)


def map_height(x):
    for i in range(3):
        if x <= MAP_X[i + 1] + 1e-9:
            t = (x - MAP_X[i]) / (MAP_X[i + 1] - MAP_X[i])
            return MAP_Z[i] * (1 - t) + MAP_Z[i + 1] * t
    raise ValueError("Map overlay outside paper")


def folded_strip(name, xs, y0, y1, offset, thickness, mat):
    """Continuous closed folded sheet, without duplicate internal seam faces."""
    vertices = [(x, y, map_height(x) + offset + dz)
                for dz in (-thickness, 0) for x in xs for y in (y0, y1)]
    n = len(xs)
    top = 2 * n
    faces = [(0, top, top + 1, 1),
             (2 * n - 2, 2 * n - 1, 4 * n - 1, 4 * n - 2)]
    for i in range(n - 1):
        a, b = 2 * i, 2 * i + 2
        faces += [(a, a + 1, b + 1, b),
                  (top + a, top + b, top + b + 1, top + a + 1),
                  (a, b, top + b, top + a),
                  (a + 1, top + a + 1, top + b + 1, b + 1)]
    return mesh(name, vertices, faces, [mat])


def build_maps(p):
    parts = [folded_strip("Three-panel cream paper map", MAP_X, -0.125, 0.125,
                          0, 0.008, p["cream"])]
    for i, y in enumerate((-0.086, 0.084), 1):
        parts.append(folded_strip(f"Palm map road {i}", MAP_X, y - 0.006,
                                  y + 0.006, 0.003, 0.004, p["palm"]))
    parts.append(folded_strip("One sand map block", (0.086, 0.151),
                              0.016, 0.062, 0.004, 0.005, p["sand"]))
    # A round head transitions to one pointed apex. The centre stays truly open;
    # the cream annulus and inner wall read as the requested cream hole.
    head = [(0.116 * math.cos(-math.pi / 6 + i * math.pi / 12),
             0.116 * math.sin(-math.pi / 6 + i * math.pi / 12))
            for i in range(17)]
    tip_z = map_height(-0.055)
    head.append((0, tip_z - 0.365))
    parts.append(pierced_plate("Clay location pin with cream hole", head,
                               (0, 0), 0.036, 0.040, p["clay"],
                               (-0.055, 0.018, 0.365), lining=p["cream"],
                               border=0.010, segments=16))
    # Box sits on the right-hand panel, with its bottom parallel to the paper.
    # A full dark band between body and lid avoids coplanar decoration.
    box_parts = [block("Kraft delivery box", (0.102, 0.092, 0.080),
                       (0, 0, 0.040), p["sand"]),
                 block("Delivery box dark lid line", (0.104, 0.094, 0.007),
                       (0, 0, 0.0825), p["brown"]),
                 block("Delivery box kraft lid", (0.108, 0.098, 0.014),
                       (0, 0, 0.092), p["sand"])]
    mount = (Matrix.Translation((0.132, -0.025, map_height(0.132) - 0.001)) @
             Matrix.Rotation(-math.atan(0.15), 4, "Y"))
    bpy.context.view_layer.update()
    for obj in box_parts:
        obj.matrix_world = mount @ obj.matrix_world
    parts += box_parts
    return parts


def ring_light(mat):
    """Closed 24 x 6 gold torus in X/Z; 16 mm thick, no curve or modifier."""
    major, minor, around, sides = 0.180, 0.008, 24, 6
    vertices = []
    for i in range(around):
        a = TAU * i / around
        for j in range(sides):
            b = TAU * j / sides
            radius = major + minor * math.cos(b)
            vertices.append((radius * math.cos(a), 0.028 + minor * math.sin(b),
                             0.415 + radius * math.sin(a)))
    faces = []
    for i in range(around):
        for j in range(sides):
            faces.append((i * sides + j, ((i + 1) % around) * sides + j,
                          ((i + 1) % around) * sides + (j + 1) % sides,
                          i * sides + (j + 1) % sides))
    return mesh("Thin gold ring light behind phone", vertices, faces, [mat])


def build_blogger(p):
    parts = []
    for i, foot in enumerate(((-0.145, -0.092, 0.009),
                               (0.145, -0.092, 0.009),
                               (0, 0.122, 0.009)), 1):
        parts.append(beam(f"Tripod dark leg {i}", foot, (0, 0.008, 0.247),
                          0.018, p["dark"]))
    parts += [cylinder("Tripod hub", 0.024, 0.035, (0, 0.008, 0.247),
                       p["dark"], segments=10),
              beam("Tripod phone mount", (0, 0.008, 0.247),
                   (0, -0.032, 0.322), 0.020, p["dark"]),
              block("Ring light lower mount", (0.018, 0.030, 0.048),
                    (0, 0.028, 0.228), p["dark"]),
              rounded_plate("Blogger landscape smartphone", 0.400, 0.200, 0.021,
                            0.046, p["dark"], (0, -0.032, 0.400)),
              rounded_plate("Blogger cream screen", 0.354, 0.156, 0.012,
                            0.010, p["cream"], (0, -0.058, 0.400)),
              ring_light(p["gold"]),
              block("Screen simple brown skewer bar", (0.278, 0.010, 0.013),
                    (0, -0.067, 0.400), p["brown"])]
    for i, x in enumerate((-0.085, 0, 0.085), 1):
        parts.append(block(f"Screen skewer cube {i}", (0.055, 0.016, 0.058),
                           (x, -0.074, 0.400), p["palm" if i == 2 else "brown"],
                           rotation=(0, 0.10 if i == 2 else -0.08, 0)))
    return parts


def build_video(p):
    """Short grill clip: raised play badge, skewer, progress and gold sparkles.

    Phone-local XYZ: X across, -Y towards the viewer, Z above its base.
    All screen details lean with the phone; the stand and sparkles stay upright.
    """
    parts = [rounded_plate("Video upright smartphone", 0.285, 0.540, 0.024,
                           0.052, p["dark"], (0, 0, 0.270)),
             rounded_plate("Video cream screen", 0.247, 0.486, 0.014,
                           0.012, p["cream"], (0, -0.029, 0.270)),
             # Screen front -0.035; badge back -0.034 attaches into it,
             # while its front -0.062 stands 27 mm proud along the normal.
             rounded_plate("Video clay rounded play badge", 0.140, 0.140, 0.035,
                           0.028, p["clay"], (0, -0.048, 0.360)),
             extrude("Video cream right-pointing play triangle",
                     [(-0.025, -0.038), (0.037, 0), (-0.025, 0.038)],
                     0.012, p["cream"], (0, -0.067, 0.360)),
             block("Video brown skewer bar", (0.196, 0.014, 0.014),
                   (0, -0.039, 0.190), p["brown"]),
             rounded_plate("Video charcoal progress track", 0.198, 0.018,
                           0.004, 0.014, p["dark"], (0, -0.040, 0.115)),
             # Left-aligned 66 mm fill over a 198 mm track: exactly one third.
             rounded_plate("Video gold one-third progress fill", 0.066, 0.018,
                           0.004, 0.014, p["gold"], (-0.066, -0.052, 0.115))]
    for i, x in enumerate((-0.060, 0, 0.060), 1):
        parts.append(block(f"Video skewer cube {i}", (0.042, 0.022, 0.046),
                           (x, -0.050, 0.190),
                           p["palm" if i == 2 else "brown"],
                           rotation=(0, 0.10 if i == 2 else -0.08, 0)))

    lean = math.radians(10)
    # Lift by the rotated body's rear half-thickness so its base meets Z=0.
    lift = 0.026 * math.sin(lean)
    mount = (Matrix.Translation((-0.050, 0, lift)) @
             Matrix.Rotation(-lean, 4, "X"))
    bpy.context.view_layer.update()
    for obj in parts:
        obj.matrix_world = mount @ obj.matrix_world
    # Endpoint is phone-local (0, 0.022, 0.240), embedded 4 mm in its back.
    attachment = (-0.050, 0.022 * math.cos(lean) + 0.240 * math.sin(lean),
                  lift - 0.022 * math.sin(lean) + 0.240 * math.cos(lean))
    parts += [beam("Video charcoal rear kickstand", (-0.050, 0.155, 0.012),
                   attachment, 0.018, p["dark"]),
              block("Video charcoal kickstand foot", (0.150, 0.028, 0.016),
                    (-0.050, 0.155, 0.008), p["dark"])]
    # Intentional decorative islands; the larger diamond rests on the floor.
    # The rightmost tip sets the complete icon's width to exactly 0.400 m.
    for label, x, z, width, height in (
            ("lower", 0.170, 0.043, 0.075, 0.086),
            ("upper", 0.180, 0.126, 0.050, 0.062)):
        parts.append(extrude(f"Video {label} gold sparkle diamond",
                             [(0, -height / 2), (width / 2, 0),
                              (0, height / 2), (-width / 2, 0)],
                             0.018, p["gold"], (x, -0.048, z)))
    return parts


def empty_scene():
    # Like the dallah generator, clear hidden objects as well as selected ones.
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def fit_and_check(parts, name):
    """Bake transforms; triangulate, recalculate normals and check closed meshes.

    No proportional fitting: in particular, thin parts retain their designed
    thickness. Intentional shallow overlaps attach food, screens and hardware.
    No UVs are needed because all materials are flat and texture-free.
    """
    bpy.context.view_layer.update()
    for obj in parts:
        assert obj.type == "MESH" and len(obj.modifiers) == 0, obj.name
        matrix = obj.matrix_world.copy()
        for vertex in obj.data.vertices:
            vertex.co = matrix @ vertex.co
        obj.matrix_world = Matrix.Identity(4)
        bm = bmesh.new()
        try:
            bm.from_mesh(obj.data)
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            assert all(edge.is_manifold for edge in bm.edges), (
                f"{name}/{obj.name}: open or non-manifold edge")
            assert all(face.calc_area() > 1e-10 for face in bm.faces), (
                f"{name}/{obj.name}: degenerate face")
            assert all(edge.calc_length() > 1e-7 for edge in bm.edges), (
                f"{name}/{obj.name}: zero-length edge")
            bm.to_mesh(obj.data)
        finally:
            bm.free()
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
        obj.data.update()
    coordinates = [v.co for obj in parts for v in obj.data.vertices]
    assert all(math.isfinite(c) for v in coordinates for c in v), name
    size = [max(v[i] for v in coordinates) - min(v[i] for v in coordinates)
            for i in range(3)]
    assert 0.38 <= size[0] <= 0.42, (name, size)
    assert 0.18 <= size[1] <= 0.27, (name, size)
    height_range = (0.20, 0.24) if name == "promo-samples" else (0.45, 0.62)
    assert height_range[0] <= size[2] <= height_range[1], (name, size)
    materials = {slot.material for obj in parts for slot in obj.material_slots}
    material_limit = 6 if name == "promo-video" else 5
    assert len(materials) <= material_limit, (name, len(materials))


def main():
    empty_scene()
    colours = palette()
    for name, builder in (("promo-samples", build_samples),
                          ("promo-chat", build_chat),
                          ("promo-maps", build_maps),
                          ("promo-blogger", build_blogger),
                          ("promo-video", build_video)):
        empty_scene()
        parts = builder(colours)
        fit_and_check(parts, name)
        objects = export_model(OUTPUT, name, parts, max_tris=1500,
                               width=(0.38, 0.42))
        bpy.context.view_layer.update()
        coordinates = [obj.matrix_world @ v.co for obj in objects
                       for v in obj.data.vertices]
        lower = [min(v[i] for v in coordinates) for i in range(3)]
        upper = [max(v[i] for v in coordinates) for i in range(3)]
        triangles = 0
        for obj in objects:
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
        path = OUTPUT / f"{name}.glb"
        assert path.is_file() and path.stat().st_size > 0, f"Missing export: {path}"
        print(f"Finished {path}: {triangles} triangles; modeling XYZ bounds "
              f"min {tuple(round(c, 6) for c in lower)} "
              f"max {tuple(round(c, 6) for c in upper)}; "
              f"{len(objects)} object, {len(objects[0].data.materials)} materials.",
              flush=True)


if __name__ == "__main__":
    main()
