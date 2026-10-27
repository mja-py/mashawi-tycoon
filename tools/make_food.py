"""Build two small, texture-free food assets with Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_food.py
Coordinates are metres, with Z up while modeling; glTF converts to +Y up.
"""

import math
from pathlib import Path
import random

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/models/food"
PREVIEWS = Path(
    "/private/tmp/claude-501/-Users-mohammadjassem-Desktop-Projects-Remaster-"
    "kebab-tycoon/52804aca-2d40-4f5a-9660-2001507966ac/scratchpad"
)
TAU = math.tau


def material(name, color, roughness=0.85):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def mesh(name, vertices, faces, materials, indices=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.materials.clear()
    for mat in materials:
        data.materials.append(mat)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    if indices is not None:
        for polygon, index in zip(data.polygons, indices):
            polygon.material_index = index
    return obj


def lathe(name, profile, materials, segments=24, wobble=0, phase=0):
    """Closed shell, profile running from lower outside to upper/inner end."""
    vertices = []
    for radius, z in profile:
        for i in range(segments):
            a = TAU * i / segments
            r = radius * (1 + wobble * math.sin(a * 3 + phase))
            vertices.append((r * math.cos(a), r * math.sin(a), z))
    faces = [tuple(reversed(range(segments)))]
    for ring in range(len(profile) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            a, b = ring * segments, (ring + 1) * segments
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple((len(profile) - 1) * segments + i
                       for i in range(segments)))
    return mesh(name, vertices, faces, materials)


def transform(obj, location, rotation=(0, 0, 0)):
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def build_pita():
    wheat = material("Pita - pale wheat", (0.78, 0.60, 0.35))
    toast = material("Toast - golden brown", (0.43, 0.235, 0.095))
    light_toast = material("Toast - honey", (0.59, 0.36, 0.15))
    parts = []
    layers = [(-0.006, 0.000, 0.00), (0.009, -0.006, 0.29),
              (-0.008, 0.006, -0.17), (0.005, 0.000, 0.13)]
    # Rounded edge, broad flat underside and gently puffed top. No square corners.
    profile = [(0.135, 0), (0.222, 0.001), (0.244, 0.007),
               (0.250, 0.019), (0.244, 0.032), (0.220, 0.039),
               (0.130, 0.043)]
    for layer, (x, y, angle) in enumerate(layers):
        bread = lathe(f"Round pita {layer + 1}", profile, [wheat],
                      segments=28, wobble=0.009, phase=layer * 1.7)
        transform(bread, (x, y, layer * 0.047), (0, 0, angle))
        parts.append(bread)

    rng = random.Random(148)
    # Flat, sparse little toast patches follow the top bread's puffed surface.
    for spot in range(11):
        angle = spot * 2.39996
        radius = math.sqrt((spot + 0.6) / 11) * 0.191
        cx, cy = radius * math.cos(angle), radius * math.sin(angle)
        size = rng.uniform(0.009, 0.021)
        vertices = []
        for i in range(9):
            a = TAU * i / 9
            r = size * rng.uniform(0.8, 1.13)
            x, y = cx + r * math.cos(a), cy + r * math.sin(a) * 0.73
            distance = math.hypot(x, y)
            z = 0.043 - max(0, distance - 0.130) * (0.004 / 0.090)
            vertices.append((x, y, z + 0.00035))
        patch = mesh(f"Toasted spot {spot + 1}", vertices,
                     [tuple(range(9))], [toast if spot % 3 == 0 else light_toast])
        transform(patch, (*layers[-1][:2], 3 * 0.047),
                  (0, 0, layers[-1][2]))
        parts.append(patch)
    return parts


def cucumber(name, skin, flesh, seeds):
    # One contiguous slice: dark skin wall, narrow skin rim and a pale cut face.
    obj = lathe(name, [(0.030, -0.008), (0.030, 0.008),
                       (0.026, 0.008)], [skin, flesh], segments=12)
    obj.data.polygons[0].material_index = 1
    obj.data.polygons[-1].material_index = 1
    parts = [obj]
    for i in range(3):
        a = i * TAU / 3
        c, s = math.cos(a), math.sin(a)
        vertices = [(c * r - s * w, s * r + c * w, 0.0082)
                    for r, w in [(0.006, -0.002), (0.017, 0),
                                 (0.006, 0.002)]]
        parts.append(mesh(f"{name} seed {i}", vertices, [(0, 1, 2)], [seeds]))
    return parts


def onion_ring(name, purple, white):
    vertices, faces, indices = [], [], []
    for i in range(12):
        a = i * TAU / 12
        for j in range(4):
            b = j * TAU / 4
            r = 0.027 + 0.004 * math.cos(b)
            vertices.append((r * math.cos(a), r * math.sin(a),
                             0.0026 * math.sin(b)))
    for i in range(12):
        for j in range(4):
            faces.append((i * 4 + j, ((i + 1) % 12) * 4 + j,
                          ((i + 1) % 12) * 4 + (j + 1) % 4,
                          i * 4 + (j + 1) % 4))
            indices.append(0 if j in (0, 3) else 1)
    return mesh(name, vertices, faces, [purple, white], indices)


def lemon_wedge(rind, pith, pulp):
    # Upright semicircular prism: yellow curved rind and inset pale cut faces.
    steps, radius, thickness = 8, 0.060, 0.023
    contour = [(radius * math.cos(i * math.pi / steps),
                radius * math.sin(i * math.pi / steps))
               for i in range(steps + 1)]
    vertices = [(x, y, z) for y in (-thickness / 2, thickness / 2)
                for x, z in contour]
    n = len(contour)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        faces.append((i, i + n, (i + 1) % n + n, (i + 1) % n))
    wedge = mesh("Lemon wedge rind", vertices, faces, [rind, pith],
                 [1, 1] + [0] * n)
    parts = [wedge]
    for side in (-1, 1):
        # Individual triangular pulp segments leave visible pith spokes.
        for i in range(steps):
            a = (i + 0.09) * math.pi / steps
            b = (i + 0.91) * math.pi / steps
            vertices = [(0, side * (thickness / 2 + 0.0002), 0.004),
                        (0.053 * math.cos(a), side * (thickness / 2 + 0.0002),
                         0.053 * math.sin(a) + 0.002),
                        (0.053 * math.cos(b), side * (thickness / 2 + 0.0002),
                         0.053 * math.sin(b) + 0.002)]
            face = (0, 1, 2) if side == -1 else (2, 1, 0)
            parts.append(mesh(f"Lemon pulp {side} {i}", vertices, [face], [pulp]))
    return parts


def build_salad():
    ceramic = material("Bowl - warm white", (0.91, 0.915, 0.88), 0.48)
    tomato = material("Tomato - red", (0.76, 0.055, 0.025))
    tomato_light = material("Tomato - coral", (0.91, 0.12, 0.045))
    skin = material("Cucumber - green skin", (0.075, 0.29, 0.065))
    flesh = material("Cucumber - pale green", (0.59, 0.78, 0.32))
    seeds = material("Cucumber - seeds", (0.81, 0.86, 0.53))
    purple = material("Onion - purple skin", (0.48, 0.12, 0.38))
    white = material("Onion - white flesh", (0.87, 0.74, 0.84))
    parsley = material("Parsley - leaf green", (0.045, 0.32, 0.055))
    rind = material("Lemon - yellow rind", (0.96, 0.64, 0.015))
    pith = material("Lemon - ivory pith", (0.97, 0.88, 0.49))
    pulp = material("Lemon - juicy yellow", (0.98, 0.75, 0.08))
    bowl = lathe("Shallow white bowl", [
        (0.109, 0), (0.142, 0.007), (0.202, 0.046),
        (0.240, 0.097), (0.250, 0.119), (0.247, 0.128),
        (0.234, 0.128), (0.229, 0.116), (0.191, 0.062),
        (0.128, 0.030)], [ceramic])
    parts = [bowl]
    rng = random.Random(917)
    # A lower bed of tomato plus a loose upper layer; keep ingredients in the bowl.
    tomato_positions = [(-0.10, -0.09), (-0.02, -0.13), (0.08, -0.10),
                        (0.14, -0.02), (0.10, 0.09), (0.01, 0.13),
                        (-0.10, 0.10), (-0.15, 0.01), (-0.06, 0.01),
                        (0.04, -0.02), (-0.05, -0.07), (0.04, 0.07),
                        (-0.02, 0.025), (0.08, 0.015)]
    for i, (x, y) in enumerate(tomato_positions):
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.object
        obj.name = f"Diced tomato {i + 1}"
        obj.data.materials.append(tomato_light if i % 4 == 0 else tomato)
        obj.scale = (rng.uniform(0.045, 0.060), rng.uniform(0.043, 0.057),
                     rng.uniform(0.037, 0.052))
        z = 0.117 if i < 10 else 0.154
        transform(obj, (x, y, z), (rng.uniform(-0.2, 0.2),
                  rng.uniform(-0.2, 0.2), rng.uniform(-1, 1)))
        parts.append(obj)

    for i, (x, y, z) in enumerate([
            (-0.12, -0.035, 0.145), (-0.055, -0.123, 0.149),
            (0.065, -0.105, 0.156), (0.139, 0.045, 0.148),
            (0.055, 0.12, 0.147), (-0.075, 0.099, 0.153),
            (-0.015, -0.023, 0.181), (0.045, 0.04, 0.181)]):
        rotation = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3),
                    rng.uniform(0, TAU))
        for obj in cucumber(f"Cucumber slice {i + 1}", skin, flesh, seeds):
            parts.append(transform(obj, (x, y, z), rotation))

    for i, (x, y, z) in enumerate([
            (-0.095, -0.087, 0.182), (0.097, -0.06, 0.180),
            (-0.092, 0.066, 0.185), (0.086, 0.086, 0.177),
            (0.006, -0.075, 0.194), (0.0, 0.068, 0.201)]):
        obj = onion_ring(f"Purple and white onion ring {i + 1}", purple, white)
        parts.append(transform(obj, (x, y, z),
                     (rng.uniform(-0.4, 0.4), rng.uniform(-0.35, 0.35), i * 0.7)))

    # Low, angular three-leaf sprigs, scattered across the visible surface.
    for i, (x, y) in enumerate([(-0.14, 0.03), (-0.04, -0.10), (0.13, -0.025),
                                (0.055, 0.09), (-0.055, 0.08), (0.02, 0.005)]):
        vertices, faces = [], []
        for j in range(3):
            a = j * TAU / 3 + i
            c, s = math.cos(a), math.sin(a)
            for r, w in [(0, 0), (0.012, -0.007), (0.025, 0), (0.012, 0.007)]:
                vertices.append((c * r - s * w, s * r + c * w, 0.001 * (r > 0)))
            faces.append(tuple(j * 4 + k for k in range(4)))
        obj = mesh(f"Parsley sprig {i + 1}", vertices, faces, [parsley])
        parts.append(transform(obj, (x, y, 0.198 + 0.003 * (i % 2))))

    # A raised wedge rests against the back rim, silhouetted above the salad.
    for obj in lemon_wedge(rind, pith, pulp):
        parts.append(transform(obj, (0.10, 0.215, 0.187),
                               (0.08, math.pi / 2, -0.40)))
    return parts


def export_asset(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    # Bake all component transforms and place the sole model origin at floor centre.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.data.calc_loop_triangles()
    triangles = len(obj.data.loop_triangles)
    assert triangles < 2000, f"{name}: {triangles} triangles exceeds budget"
    assert min(v.co.z for v in obj.data.vertices) >= -0.00001
    print(f"{name}: {triangles} triangles; dimensions "
          f"{obj.dimensions.x:.3f} x {obj.dimensions.y:.3f} x {obj.dimensions.z:.3f} m",
          flush=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{name}.glb"),
                              export_format="GLB", export_apply=True,
                              export_yup=True, use_selection=True,
                              export_cameras=False, export_lights=False)
    return obj


def preview(obj, filename):
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
    bpy.context.object.data.materials.append(ground)
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
    fill.rotation_euler = (Vector((0, 0, 0.09)) - fill.location).to_track_quat(
        "-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=(0.75, -1.05, 0.91))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.70
    camera.rotation_euler = (Vector((0, 0, 0.105)) - camera.location).to_track_quat(
        "-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = str(PREVIEWS / filename)
    bpy.ops.render.render(write_still=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    for builder, name, image in [(build_pita, "pita-stack", "pita_preview.png"),
                                 (build_salad, "salad-bowl", "salad_preview.png")]:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        obj = export_asset(builder(), name)
        preview(obj, image)
    print("Finished both GLB exports and 512 x 512 previews.", flush=True)


if __name__ == "__main__":
    main()
