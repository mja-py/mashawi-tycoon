"""Build one low-poly, texture-free hospitality icon with Blender 5.2.

Run from the project root: /opt/homebrew/bin/blender -b -P tools/make_icon_dallah.py
Metres, Z up during modeling, +Y up in GLB; origin at bounding-box base centre.
Uses the same flat materials and GLB exporter as make_icons_a/b/c.py.
Only writes assets/models/icons/dallah.glb; no preview or .blend is saved.
"""

import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_furniture import ball, export_model, lathe, material, mesh, metal, tube


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/models/icons"
TAU = math.tau
# Measured from the shipped speaker.glb, converted back to modeling X/Y/Z.
SIZE = (0.400, 0.244500005, 0.618501604)
POT = Vector((-0.022, 0.022, 0))


def placed(obj):
    obj.location = POT
    return obj


def spout(brass, dark):
    """Broad-rooted crescent, tapering to a small recessed pouring mouth.

    Each ring is elliptical: broad in the silhouette's X/Z plane, narrow
    through Y. This gives the characteristic blade-like dallah spout rather
    than a straight kettle nozzle. The first ring is buried in the belly.
    """
    profile = [(0.062, 0.199, 0.043, 0.027),
               (0.103, 0.226, 0.036, 0.024),
               (0.137, 0.267, 0.028, 0.020),
               (0.160, 0.315, 0.021, 0.016),
               (0.176, 0.365, 0.016, 0.013),
               (0.187, 0.411, 0.012, 0.010),
               (0.203, 0.449, 0.009, 0.008),
               (0.228, 0.477, 0.007, 0.007)]
    points = [Vector((x, 0, z)) for x, z, _, _ in profile]
    sides = 6
    vertices, faces = [], [tuple(reversed(range(sides)))]
    frames = []
    for i, (point, (_, _, width, depth)) in enumerate(zip(points, profile)):
        tangent = (points[min(i + 1, len(points) - 1)] -
                   points[max(0, i - 1)]).normalized()
        u = Vector((tangent.z, 0, -tangent.x))
        v = Vector((0, 1, 0))
        frames.append((tangent, u, v))
        vertices += [tuple(point + width * math.cos(TAU * j / sides) * u +
                           depth * math.sin(TAU * j / sides) * v)
                     for j in range(sides)]
    for i in range(len(points) - 1):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    # Fold the lip inward, then recess the dark mouth: no coplanar black decal.
    tangent, u, v = frames[-1]
    for centre, radius in ((points[-1], 0.0048),
                           (points[-1] - tangent * 0.008, 0.0038)):
        vertices += [tuple(centre + radius * (math.cos(TAU * j / sides) * u +
                                             math.sin(TAU * j / sides) * v))
                     for j in range(sides)]
    for ring in (len(points) - 1, len(points)):
        for j in range(sides):
            a, b = ring * sides + j, ring * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(range(len(vertices) - sides, len(vertices))))
    obj = mesh("Dallah crescent spout", vertices, faces, [brass, dark])
    obj.data.polygons[-1].material_index = 1
    return placed(obj)


def finial(brass):
    """A turned knob with a single real apex, avoiding zero-radius rings."""
    profile = [(0.015, 0.503), (0.021, 0.514),
               (0.014, 0.529), (0.008, 0.541)]
    sides = 10
    vertices = [(r * math.cos(TAU * j / sides),
                 r * math.sin(TAU * j / sides), z)
                for r, z in profile for j in range(sides)]
    faces = [tuple(reversed(range(sides)))]
    for ring in range(len(profile) - 1):
        for j in range(sides):
            a, b = ring * sides + j, ring * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    apex = len(vertices)
    vertices.append((0, 0, 0.560))
    start = (len(profile) - 1) * sides
    faces += [(start + j, start + (j + 1) % sides, apex)
              for j in range(sides)]
    return placed(mesh("Dallah pointed finial", vertices, faces, [brass]))


def build_dallah():
    brass = metal("Dallah - warm brass", (0.83, 0.53, 0.16))
    band = metal("Dallah - darker waist brass", (0.59, 0.35, 0.10))
    white = material("Dallah - white porcelain", (0.96, 0.94, 0.88), 0.38)
    dates = material("Dallah - dark dates", (0.105, 0.039, 0.015), 0.7)
    mouth = material("Dallah - spout interior", (0.075, 0.041, 0.018))

    body = placed(lathe("Dallah belly waist and flared neck",
                        [(0.052, 0.016), (0.061, 0.033), (0.082, 0.080),
                         (0.092, 0.140), (0.085, 0.199), (0.060, 0.251),
                         (0.044, 0.278), (0.044, 0.299), (0.060, 0.355),
                         (0.076, 0.415), (0.077, 0.430)],
                        [brass, band], segments=14))
    # One integrated strip, with no overlapping cylinder at the waist.
    for polygon in body.data.polygons:
        if 1 + 6 * 14 <= polygon.index < 1 + 7 * 14:
            polygon.material_index = 1
    pot = [body,
           placed(lathe("Dallah domed lid",
                        [(0.078, 0.428), (0.083, 0.437), (0.076, 0.449),
                         (0.060, 0.478), (0.035, 0.499), (0.012, 0.508)],
                        [brass], segments=14)),
           finial(brass), spout(brass, mouth),
           placed(tube("Dallah curved rear handle",
                       [(-0.064, 0, 0.399), (-0.106, 0, 0.418),
                        (-0.143, 0, 0.400), (-0.160, 0, 0.361),
                        (-0.163, 0, 0.313), (-0.150, 0, 0.267),
                        (-0.121, 0, 0.229), (-0.077, 0, 0.211)],
                       0.012, brass, sides=6))]

    # The tray remains circular; only the pot assembly is fitted in X/Y.
    # The spout/handle can overhang its rim, as on a real serving tray.
    parts = [lathe("Round brass serving tray",
                   [(0.112, 0), (SIZE[1] / 2, 0.006),
                    (SIZE[1] / 2, 0.019), (0.113, 0.019),
                    (0.109, 0.016)], [brass], segments=20)]
    for i, (x, y) in enumerate(((-0.049, -0.080), (0.017, -0.088))):
        cup = lathe(f"White handleless finjan {i + 1}",
                    [(0.016, 0.016), (0.020, 0.022), (0.028, 0.072),
                     (0.023, 0.072), (0.014, 0.025)],
                    [white], segments=10)
        cup.location = (x, y, 0)
        parts.append(cup)
    # Five dates in the lower layer and one on top, all deliberately touching.
    for i, (x, y, z, angle) in enumerate(
            ((0.065, -0.023, 0.026, -0.4), (0.092, -0.022, 0.026, 0.2),
             (0.063, 0.003, 0.026, 0.6), (0.090, 0.004, 0.026, -0.5),
             (0.077, 0.027, 0.026, 0.3), (0.078, 0.001, 0.044, -0.3))):
        date = ball(f"Date {i + 1}", 1, (x, y, z), dates,
                    subdivisions=1, scale=(0.013, 0.021, 0.012))
        date.rotation_euler.z = angle
        parts.append(date)
    return parts + pot, pot


def fit_and_check(parts, pot):
    """Bake transforms, fit the speaker envelope, and check closed flat meshes."""
    bpy.context.view_layer.update()
    for obj in parts:
        matrix = obj.matrix_world.copy()
        for vertex in obj.data.vertices:
            vertex.co = matrix @ vertex.co
        obj.matrix_world = Matrix.Identity(4)
    coordinates = [v.co for obj in pot for v in obj.data.vertices]
    factor = SIZE[0] / (max(v.x for v in coordinates) -
                        min(v.x for v in coordinates))
    for obj in pot:
        for vertex in obj.data.vertices:
            vertex.co.x = POT.x + (vertex.co.x - POT.x) * factor
            vertex.co.y = POT.y + (vertex.co.y - POT.y) * factor
    height = max(v.co.z for obj in parts for v in obj.data.vertices)
    for obj in parts:
        for vertex in obj.data.vertices:
            vertex.co.z *= SIZE[2] / height
        bm = bmesh.new()
        try:
            bm.from_mesh(obj.data)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            assert all(edge.is_manifold for edge in bm.edges), (
                f"{obj.name}: open or non-manifold edge")
            assert all(face.calc_area() > 1e-10 for face in bm.faces), (
                f"{obj.name}: degenerate face")
            bm.to_mesh(obj.data)
        finally:
            bm.free()
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
        obj.data.update()


def main():
    # Data API cleanup also removes hidden/unselected objects and works without
    # assuming a factory Cube, a particular cursor position, or an active mode.
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    parts, pot = build_dallah()
    fit_and_check(parts, pot)
    objects = export_model(OUTPUT, "dallah", parts, max_tris=1500,
                           width=(SIZE[0] - 1e-5, SIZE[0] + 1e-5))
    bpy.context.view_layer.update()
    coordinates = [obj.matrix_world @ v.co for obj in objects
                   for v in obj.data.vertices]
    lower = [min(v[i] for v in coordinates) for i in range(3)]
    upper = [max(v[i] for v in coordinates) for i in range(3)]
    size = [upper[i] - lower[i] for i in range(3)]
    assert all(abs(size[i] - SIZE[i]) < 1e-5 for i in range(3)), size
    triangles = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    path = OUTPUT / "dallah.glb"
    assert path.is_file() and path.stat().st_size > 0, f"Missing export: {path}"
    print(f"Finished {path}: {triangles} triangles; "
          f"bounding box (modeling XYZ, metres) min {tuple(round(c, 6) for c in lower)} "
          f"max {tuple(round(c, 6) for c in upper)}; "
          f"{len(objects)} object, {len(objects[0].data.materials)} materials.",
          flush=True)


if __name__ == "__main__":
    main()
