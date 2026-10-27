"""Build two texture-free, low-poly doner assets with Blender 5.2.

Run from any directory: blender -b -P /path/to/tools/make_doner.py
Blender uses Z up; the standard glTF exporter converts this to +Y up.
Only the joined asset mesh is exported, never the preview stage or lights.
"""

import json
import math
from pathlib import Path
import random
import struct

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/models/food"
PREVIEWS = Path(
    "/private/tmp/claude-501/-Users-mohammadjassem-Desktop-Projects-Remaster-"
    "kebab-tycoon/52804aca-2d40-4f5a-9660-2001507966ac/scratchpad"
)
TAU = math.tau
RNG = random.Random(23)


def material(name, hex_color, metallic=0.0, roughness=0.85):
    def linear(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    color = tuple(linear(hex_color[i:i + 2]) for i in (0, 2, 4)) + (1,)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
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
    if indices:
        for polygon, index in zip(data.polygons, indices):
            polygon.material_index = index
    # All custom mesh coordinates are in asset space: every origin is (0,0,0).
    return obj


def lathe(name, profile, mat, sides=16, center=(0, 0)):
    """Closed surface of revolution; profile travels out along the bottom."""
    verts, rings, faces = [], [], []
    for radius, z in profile:
        if radius == 0:
            rings.append([len(verts)])
            verts.append((center[0], center[1], z))
        else:
            ring = []
            for i in range(sides):
                a = TAU * i / sides
                ring.append(len(verts))
                verts.append((center[0] + radius * math.cos(a),
                              center[1] + radius * math.sin(a), z))
            rings.append(ring)
    for lower, upper in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            if len(lower) == 1:
                faces.append((lower[0], upper[j], upper[i]))
            elif len(upper) == 1:
                faces.append((lower[i], lower[j], upper[0]))
            else:
                faces.append((lower[i], lower[j], upper[j], upper[i]))
    return mesh(name, verts, faces, [mat])


def meat_layer(index, crust, inner):
    z = 0.185 + index * 0.05
    radius = (0.105 + 0.118 * index / 13) * RNG.uniform(0.95, 1.05)
    # Bottom seven layers have a real missing wedge, not an overlaid decal.
    # The two exposed radial walls receive the pale cooked-meat material.
    carved = index < 7
    if carved:
        half_angle = math.radians(48)
        outline = [
            (radius * math.cos(a), radius * math.sin(a))
            for a in (-math.pi / 2 + half_angle
                      + (TAU - 2 * half_angle) * j / 14 for j in range(15))
        ]
        outline.append((0, -radius * (0.13 if index < 6 else 0.40)))
    else:
        outline = [(radius * math.cos(TAU * j / 16),
                    radius * math.sin(TAU * j / 16)) for j in range(16)]
    count = len(outline)
    # Slightly bevel each layer's silhouette with a narrower upper ring.
    verts = [(x, y, z) for x, y in outline]
    verts += [(x * 0.976, y * 0.976, z + 0.05) for x, y in outline]
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    indices = [0, 0]
    for j in range(count):
        k = (j + 1) % count
        faces.append((j, k, k + count, j + count))
        indices.append(1 if carved and j >= count - 2 else 0)
    return mesh(f"Meat layer {index + 1:02d}", verts, faces,
                [crust, inner], indices)


def ribbon(name, path, width, thickness, top_mat, edge_mat):
    """Faceted solid ribbon following a 3-D path, with a contrasting edge."""
    verts = []
    for i, point in enumerate(path):
        tangent = Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(0, i - 1)])
        side = Vector((-tangent.y, tangent.x, 0)).normalized() * width / 2
        point = Vector(point)
        verts.extend([tuple(point - side), tuple(point + side),
                      tuple(point - side - Vector((0, 0, thickness))),
                      tuple(point + side - Vector((0, 0, thickness)))])
    faces, indices = [(0, 2, 3, 1)], [1]
    for i in range(len(path) - 1):
        a, b = i * 4, (i + 1) * 4
        faces.extend([(a, a + 1, b + 1, b), (a + 2, b + 2, b + 3, a + 3),
                      (a, b, b + 2, a + 2), (a + 1, a + 3, b + 3, b + 1)])
        indices.extend([0, 1, 1, 1])
    a = (len(path) - 1) * 4
    faces.append((a, a + 1, a + 3, a + 2))
    indices.append(1)
    return mesh(name, verts, faces, [top_mat, edge_mat], indices)


def build_spit(m):
    lathe("Dark metal drip tray", [(0, 0), (0.245, 0), (0.268, 0.014),
          (0.268, 0.038), (0.250, 0.038), (0.242, 0.023), (0, 0.023)],
          m["tray"], 20)
    lathe("Vertical steel skewer", [(0, 0.023), (0.010, 0.023),
          (0.010, 0.980), (0, 0.980)], m["steel"], 10)
    lathe("Lower meat support", [(0, 0.158), (0.090, 0.158),
          (0.090, 0.176), (0, 0.176)], m["steel"], 12)
    lathe("Top steel knob", [(0, 0.966), (0.021, 0.966), (0.026, 0.983),
          (0.017, 1.0), (0, 1.0)], m["steel"], 10)
    for i in range(14):
        meat_layer(i, m["crust"][i % len(m["crust"])], m["inner"][i % 2])
    lathe("Small serving plate", [(0, 0.026), (0.084, 0.026), (0.123, 0.039),
          (0.123, 0.049), (0.108, 0.053), (0.081, 0.037), (0, 0.037)],
          m["plate"], 16, (0, -0.258))
    for i in range(4):
        path = []
        for j in range(7):
            t = j / 6
            path.append((-0.082 + t * 0.155,
                         -0.315 + i * 0.035 + 0.010 * math.sin(t * TAU + i),
                         0.054 + i * 0.002 + 0.010 * math.sin(t * math.pi)
                         + 0.022 * max(0, (t - 0.72) / 0.28) ** 2))
        ribbon(f"Curled shaved meat {i + 1}", path, 0.021, 0.004,
               m["inner"][i % 2], m["crust"][i % 3])


def pita_shell(m):
    # A thick half-cylinder with folded sides; a front opening shows fillings.
    n = 14
    angles = [math.radians(-39 + 258 * i / n) for i in range(n + 1)]
    verts = []
    for z, radius in [(0.056, 0.060), (0.254, 0.081),
                      (0.056, 0.052), (0.254, 0.072)]:
        for i, a in enumerate(angles):
            edge = 0.004 * math.sin(i * 2.1) if z > 0.2 else 0
            verts.append((radius * math.cos(a), radius * math.sin(a), z + edge))
    stride = n + 1
    faces, indices = [], []
    for i in range(n):
        faces.extend([(i, i + 1, stride + i + 1, stride + i),
                      (2 * stride + i, 3 * stride + i, 3 * stride + i + 1,
                       2 * stride + i + 1),
                      (stride + i, stride + i + 1, 3 * stride + i + 1, 3 * stride + i),
                      (i, 2 * stride + i, 2 * stride + i + 1, i + 1)])
        indices.extend([0 if i % 4 else 1, 2, 2, 0])
    for i in (0, n):
        face = (i, stride + i, 3 * stride + i, 2 * stride + i)
        faces.append(tuple(reversed(face)) if i == n else face)
        indices.append(2)
    mesh("Folded half-cylinder pita", verts, faces,
         [m["pita"], m["toast"], m["crumb"]], indices)


def build_wrap(m):
    pita_shell(m)
    lathe("Ivory paper wrap band", [(0, 0), (0.060, 0), (0.074, 0.139),
          (0.072, 0.144), (0.069, 0.139), (0.055, 0.008), (0, 0.008)],
          m["paper"], 14)
    lathe("Terracotta paper stripe", [(0.0640, 0.038), (0.0647, 0.038),
          (0.0661, 0.051), (0.0654, 0.051), (0.0640, 0.038)], m["stripe"], 14)
    lathe("Meat inside pita", [(0, 0.120), (0.048, 0.120), (0.064, 0.244),
          (0.052, 0.267), (0, 0.267)], m["inner"][0], 10)
    # Folded, angular lettuce leaves reach out of the open end.
    for i in range(6):
        a = TAU * i / 6 + 0.25
        radial = Vector((math.cos(a), math.sin(a), 0))
        across = Vector((-math.sin(a), math.cos(a), 0))
        base = radial * 0.046 + Vector((0, 0, 0.245))
        tip_height = 0.30 if i == 1 else 0.285 + 0.008 * (i % 2)
        points = [base - across * 0.023,
                  base + radial * 0.032 - across * 0.019 + Vector((0, 0, 0.028)),
                  radial * 0.078 + Vector((0, 0, tip_height)),
                  base + radial * 0.025 + across * 0.021 + Vector((0, 0, 0.026)),
                  base + across * 0.022,
                  base + radial * 0.015 + Vector((0, 0, 0.027))]
        faces = [(j, (j + 1) % 5, 5) for j in range(5)]
        faces += [tuple(reversed(face)) for face in faces[:]]
        mesh(f"Folded lettuce {i + 1}", points, faces,
             [m["lettuce"], m["lettuce_light"]], [0, 1, 0, 1, 0] * 2)
    for i in range(5):
        x = -0.047 + i * 0.022
        path = [(x + 0.009 * math.sin(j * 0.8 + i),
                 -0.057 + j * 0.018, 0.253 + 0.018 * math.sin(j / 5 * math.pi)
                 + (i % 2) * 0.009) for j in range(6)]
        ribbon(f"Exposed meat strip {i + 1}", path, 0.016, 0.004,
               m["inner"][i % 2], m["crust"][i % 3])
    for i, (x, y, z) in enumerate([(-0.043, -0.035, 0.277),
                                  (0.036, -0.030, 0.279), (0.013, 0.041, 0.281)]):
        lathe(f"Tomato piece {i + 1}", [(0, z - 0.006), (0.020, z - 0.006),
              (0.024, z + 0.003), (0.014, z + 0.008), (0, z + 0.008)],
              m["tomato"], 5, (x, y))


def join_asset(name):
    bpy.ops.object.select_all(action="DESELECT")
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    # Explicit triangulation makes the exported budget deterministic.
    modifier = obj.modifiers.new("Export triangulation", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def export_asset(obj, filename, height):
    zs = [v.co.z for v in obj.data.vertices]
    assert abs(min(zs)) < 1e-6, "Asset must touch Z=0"
    assert abs(max(zs) - min(zs) - height) < 1e-6, "Unexpected asset height"
    triangles = len(obj.data.polygons)
    assert triangles < 2500, f"Triangle budget exceeded: {triangles}"
    assert obj.location.length < 1e-8, "Origin must be the base center"
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / filename), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True,
                              export_materials="EXPORT", export_cameras=False,
                              export_lights=False)
    # Check the GLB itself, including conversion to Y up and exported materials.
    data = (OUTPUT / filename).read_bytes()
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    gltf = json.loads(data[20:20 + length])
    primitives = [p for item in gltf["meshes"] for p in item["primitives"]]
    exported_tris = sum(gltf["accessors"][p["indices"]]["count"] // 3 for p in primitives)
    positions = [gltf["accessors"][p["attributes"]["POSITION"]] for p in primitives]
    ymin = min(a["min"][1] for a in positions)
    ymax = max(a["max"][1] for a in positions)
    assert abs(ymin) < 1e-6 and abs(ymax - height) < 1e-6
    assert exported_tris == triangles and exported_tris < 2500
    assert all("material" in p for p in primitives)
    assert not gltf.get("textures"), "Assets should contain flat colors only"
    print(f"VERIFIED {filename}: {exported_tris} triangles; Y-up height "
          f"{ymax - ymin:.6f}; origin (0, 0, 0); {len(gltf['materials'])} materials",
          flush=True)
    return triangles


def preview(obj, filename, height):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.7, 0.76, 0.85, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.001))
    bpy.context.object.data.materials.append(material("Preview ground", "E6E1D8"))
    bpy.ops.object.camera_add(location=(1.45 * height, -2.8 * height, 1.65 * height))
    camera = bpy.context.object
    target = Vector((0, -0.025 * height, 0.46 * height))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = height * 1.28
    camera.data.lens = 50
    camera.data.clip_start = 0.001
    scene.camera = camera
    bpy.ops.object.light_add(type="SUN", location=(2, -3, 5))
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(25), math.radians(-25), math.radians(-30))
    sun.data.energy = 2.2
    sun.data.angle = math.radians(18)
    bpy.ops.object.light_add(type="AREA", location=(-height, -height, 2 * height))
    fill = bpy.context.object
    fill.rotation_euler = (target - fill.location).to_track_quat("-Z", "Y").to_euler()
    fill.data.energy = 35 * height ** 2
    fill.data.shape = "DISK"
    fill.data.size = height * 2
    scene.render.filepath = str(PREVIEWS / filename)
    bpy.ops.render.render(write_still=True)
    print(f"PREVIEW {scene.render.filepath}", flush=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def main():
    RNG.seed(23)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    clear_scene()
    mats = {
        "tray": material("Charcoal drip tray", "454D53", 0.65, 0.50),
        "steel": material("Brushed steel", "B4BDC1", 0.72, 0.38),
        "plate": material("Warm white ceramic", "EAE3D2"),
        "crust": [material("Roast " + str(i), color) for i, color in enumerate(
            ["97502A", "B36B38", "A15B30", "C18148", "A85E30"])],
        "inner": [material("Carved interior " + str(i), color)
                  for i, color in enumerate(["D69C68", "C98A55"])],
        "pita": material("Golden pita", "DBAF70"),
        "toast": material("Toasted pita facets", "C69555"),
        "crumb": material("Pita crumb", "F1D49C"),
        "paper": material("Ivory paper", "F4EFDF"),
        "stripe": material("Paper terracotta band", "BE6543"),
        "lettuce": material("Lettuce green", "57913B"),
        "lettuce_light": material("Lettuce folded edge", "8EBA50"),
        "tomato": material("Tomato red", "D84A32"),
    }
    build_spit(mats)
    spit = join_asset("Doner spit")
    spit_count = export_asset(spit, "doner-spit.glb", 1.0)
    preview(spit, "doner_preview.png", 1.0)
    clear_scene()
    build_wrap(mats)
    wrap = join_asset("Doner wrap")
    wrap_count = export_asset(wrap, "doner-wrap.glb", 0.3)
    preview(wrap, "wrap_preview.png", 0.3)
    assert spit_count + wrap_count < 2500, "Combined asset budget exceeded"
    print(f"DONE: spit {spit_count}; wrap {wrap_count}; combined "
          f"{spit_count + wrap_count} triangles (<2500).", flush=True)


if __name__ == "__main__":
    main()
