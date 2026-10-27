"""Build ten low-poly, texture-free marketing and dessert assets in Blender 5.2.

Run from any directory: /opt/homebrew/bin/blender -b -P tools/make_icons_b.py
Metres, Z up while modeling, +Y up in GLB; origins at the bounding-box base centre.
All exports finish before 512 x 512 EEVEE previews. Optional: -- --no-previews.
"""

import math
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_mashawi import (box, fleck, lathe, material, mesh, metal, place,
                          preview, rounded_rectangle, transform, PREVIEWS, TAU)


ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "assets/models/icons"
FOOD = ROOT / "assets/models/food"


def block(name, size, location, mat, bevel=0, rotation=(0, 0, 0)):
    return transform(box(name, size, mat, bevel), location, rotation)


def silhouette(name, contour, depth, mat):
    """Extrude an anticlockwise X/Z outline, facing the preview's negative Y."""
    area = sum(x * contour[(i + 1) % len(contour)][1] -
               contour[(i + 1) % len(contour)][0] * z
               for i, (x, z) in enumerate(contour))
    if area < 0:
        contour = list(reversed(contour))
    n = len(contour)
    vertices = [(x, y, z) for y in (-depth / 2, depth / 2) for x, z in contour]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    return mesh(name, vertices, faces, [mat])


def tube(name, points, radius, mat, sides=4):
    """Faceted, capped tube along a polyline; no curves or export modifiers."""
    points = [Vector(p) for p in points]
    vertices = []
    for i, point in enumerate(points):
        tangent = (points[min(i + 1, len(points) - 1)] -
                   points[max(0, i - 1)]).normalized()
        reference = Vector((0, 1, 0)) if abs(tangent.y) < 0.9 else Vector((1, 0, 0))
        u = tangent.cross(reference).normalized()
        v = tangent.cross(u).normalized()
        for j in range(sides):
            a = TAU * j / sides
            vertices.append(tuple(point + radius * (u * math.cos(a) + v * math.sin(a))))
    faces = [tuple(reversed(range(sides)))]
    for i in range(len(points) - 1):
        faces += [(i * sides + j, i * sides + (j + 1) % sides,
                   (i + 1) * sides + (j + 1) % sides, (i + 1) * sides + j)
                  for j in range(sides)]
    faces.append(tuple((len(points) - 1) * sides + j for j in range(sides)))
    return mesh(name, vertices, faces, [mat])


def cylinder(name, radius, depth, location, mat, segments=12, rotation=(0, 0, 0)):
    obj = lathe(name, [(radius, -depth / 2), (radius, depth / 2)],
                [mat], segments=segments)
    return transform(obj, location, rotation)


def dome(name, radius, height, location, mat, segments=16):
    profile = [(radius, 0), (radius * 0.95, height * 0.40),
               (radius * 0.72, height * 0.78), (radius * 0.36, height * 0.97),
               (radius * 0.08, height)]
    return transform(lathe(name, profile, [mat], segments=segments), location)


def dome_surface(radius, height, distance):
    """Height on the actual faceted dome profile, for seated garnishes."""
    profile = [(0, 1), (0.08, 1), (0.36, 0.97), (0.72, 0.78),
               (0.95, 0.40), (1, 0)]
    fraction = distance / radius
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        if fraction <= r1:
            return height * (z0 + (z1 - z0) * (fraction - r0) / (r1 - r0))
    return 0


def glass_material(name, color, alpha):
    glass = material(name, color, 0.15)
    shader = glass.node_tree.nodes["Principled BSDF"]
    shader.inputs["Alpha"].default_value = alpha
    shader.inputs["Transmission Weight"].default_value = 0.12
    shader.inputs["IOR"].default_value = 1.45
    glass.diffuse_color = (*color, alpha)
    glass.surface_render_method = "DITHERED"
    return glass


def flame(name, mat):
    return silhouette(name, [(-0.030, 0.005), (-0.039, 0.026), (-0.025, 0.052),
                              (-0.019, 0.034), (0.004, 0.081), (0.014, 0.055),
                              (0.032, 0.037), (0.037, 0.017), (0.022, 0.002),
                              (0, -0.006)], 0.001, mat)


def paper(cream, red, orange, ink, name):
    # Model flat on XY first; the same assembly also becomes the upright flier.
    parts = [block(name, (0.205, 0.276, 0.002), (0, 0, 0.001), cream),
             block(name + " red header", (0.183, 0.027, 0.0008),
                   (0, 0.100, 0.0024), red)]
    logo = flame(name + " orange flame", orange)
    parts.append(transform(logo, (0, -0.012, 0.0034), (-math.pi / 2, 0, 0)))
    for i, width in enumerate((0.132, 0.150, 0.099)):
        parts.append(block(name + f" print line {i + 1}", (width, 0.006, 0.0007),
                           (0, -0.064 - i * 0.015, 0.0024), ink))
    return parts


def build_fliers():
    cream = material("Fliers - cream paper", (0.98, 0.91, 0.73))
    red = material("Fliers - red stripe", (0.69, 0.055, 0.045))
    orange = material("Fliers - orange flame", (1.0, 0.36, 0.025))
    ink = material("Fliers - printed brown", (0.28, 0.12, 0.07))
    parts = []
    for i in range(4):
        parts.extend(place(paper(cream, red, orange, ink, f"Fanned flier {i + 1}"),
                           ((i - 1.5) * 0.024, -0.025, i * 0.0035),
                           (0, 0, (i - 1.5) * 0.21)))
    # Lower edge touches the stack; printed face points toward negative Y.
    parts.extend(place(paper(cream, red, orange, ink, "Upright hand-sized flier"),
                       (0.025, 0.086, 0.150), (math.pi / 2, 0, -0.12)))
    return parts


def build_posters():
    frame = material("Poster - charcoal frame", (0.075, 0.065, 0.065))
    orange = material("Poster - bright orange paper", (1.0, 0.33, 0.025))
    cream = material("Poster - cream headline", (1.0, 0.91, 0.67))
    parts = [block("Poster dark frame", (0.36, 0.030, 0.40), (0, 0, 0.285), frame, 0.008),
             block("Orange poster", (0.322, 0.004, 0.361), (0, -0.018, 0.285), orange),
             block("Poster headline", (0.231, 0.002, 0.018), (0, -0.021, 0.421), cream)]
    for x in (-0.130, 0.130):
        parts.append(block("Street board leg", (0.025, 0.026, 0.13), (x, 0, 0.065), frame))
        parts.append(block("Street board foot", (0.065, 0.20, 0.016), (x, 0, 0.008), frame, 0.004))
    # Grill bowl, legs and two chunky skewers are all solid dark silhouettes.
    contour = [(-0.102, 0.26), (-0.073, 0.213), (0.070, 0.213), (0.102, 0.26)]
    parts.append(transform(silhouette("Poster grill silhouette", contour, 0.002, frame),
                           (0, -0.022, 0)))
    for x in (-0.057, 0.057):
        parts.append(block("Printed grill leg", (0.012, 0.002, 0.052),
                           (x, -0.022, 0.192), frame, rotation=(0, x * 3, 0)))
    for row in range(2):
        parts.append(block("Printed skewer blade", (0.25, 0.002, 0.007),
                           (0, -0.023, 0.297 + row * 0.042), frame))
        for x in (-0.064, -0.020, 0.024, 0.068):
            parts.append(block("Printed skewer morsel", (0.033, 0.002, 0.025),
                               (x, -0.024, 0.302 + row * 0.042), frame,
                               rotation=(0, 0.14, 0)))
    return parts


def build_social():
    shell = material("Phone - charcoal shell", (0.055, 0.045, 0.075), 0.35)
    pink = material("Phone - screen pink", (0.94, 0.095, 0.32), 0.48)
    orange = material("Phone - screen orange", (1.0, 0.36, 0.075), 0.48)
    white = material("Phone - white camera icon", (1.0, 0.96, 0.88))
    parts = [block("Upright smartphone", (0.228, 0.034, 0.422), (0, 0, 0.211), shell, 0.018),
             block("Upper pink screen", (0.202, 0.002, 0.193), (0, -0.018, 0.307), pink, 0.009),
             block("Lower orange screen", (0.202, 0.002, 0.193), (0, -0.018, 0.114), orange, 0.009),
             block("Phone earpiece", (0.054, 0.002, 0.006), (0, -0.020, 0.399), shell, 0.002)]
    # A true rounded rectangular outline leaves the two-colour screen visible.
    outer = rounded_rectangle(0.070, 0.054, 0.018, steps=3)
    inner = rounded_rectangle(0.057, 0.041, 0.008, steps=3)
    vertices = [(x, -0.021, z + 0.232) for contour in (outer, inner) for x, z in contour]
    n = len(outer)
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    parts.append(mesh("White rounded camera outline", vertices, faces, [white]))
    lens = [(0.025 * math.cos(i * TAU / 16), -0.022,
             0.232 + 0.025 * math.sin(i * TAU / 16)) for i in range(16)]
    # Ring lens rather than an opaque disc.
    lens += [(0.015 * math.cos(i * TAU / 16), -0.022,
              0.232 + 0.015 * math.sin(i * TAU / 16)) for i in range(16)]
    parts.append(mesh("White camera lens", lens,
                      [(i, (i + 1) % 16, 16 + (i + 1) % 16, 16 + i) for i in range(16)], [white]))
    parts.append(block("Camera top tab", (0.045, 0.002, 0.013), (0.024, -0.021, 0.290), white, 0.004))
    heart = [(-0.046, 0.010), (0, -0.041), (0.046, 0.010), (0.047, 0.033),
             (0.030, 0.045), (0.013, 0.042), (0, 0.028), (-0.013, 0.042),
             (-0.030, 0.045), (-0.047, 0.033)]
    parts.append(transform(silhouette("Floating pink heart", heart, 0.019, pink),
                           (0.202, 0, 0.312), (0, -0.12, 0)))
    return parts


def build_radio():
    brown = material("Radio - walnut case", (0.30, 0.115, 0.045))
    cream = material("Radio - cream face", (0.92, 0.81, 0.60))
    dark = material("Radio - dark speaker", (0.09, 0.065, 0.045))
    gold = material("Radio - warm gold", (0.85, 0.53, 0.15), 0.42)
    steel = metal("Radio - antenna steel")
    parts = [block("Vintage rounded radio case", (0.316, 0.126, 0.216),
                   (-0.035, 0, 0.133), brown, 0.016),
             block("Cream radio face", (0.292, 0.008, 0.190),
                   (-0.035, -0.065, 0.133), cream, 0.009)]
    for x in (-0.145, 0.075):
        parts.append(block("Radio short foot", (0.030, 0.065, 0.025), (x, 0, 0.0125), dark, 0.004))
    face_rotation = (math.pi / 2, 0, 0)
    parts.append(cylinder("Round speaker grille", 0.073, 0.009, (-0.094, -0.074, 0.137),
                          dark, 20, face_rotation))
    # Sparse cream bars across a dark disc read as a circular perforated grille.
    for i in range(-4, 5):
        z = i * 0.013
        width = 2 * math.sqrt(0.067 ** 2 - z ** 2)
        parts.append(block("Speaker grille slat", (width, 0.003, 0.0035),
                           (-0.094, -0.080, 0.137 + z), brown))
    parts.append(block("Radio tuning display", (0.093, 0.003, 0.026), (0.065, -0.071, 0.190), dark))
    for i in range(5):
        parts.append(block("Tuner scale tick", (0.003, 0.002, 0.014),
                           (0.032 + i * 0.016, -0.074, 0.190), gold))
    for x in (0.037, 0.093):
        parts.append(cylinder("Round tuning knob", 0.019, 0.018, (x, -0.080, 0.100), gold, 12, face_rotation))
        parts.append(block("Knob index", (0.003, 0.001, 0.010), (x, -0.090, 0.106), dark))
    parts.append(tube("Tilted antenna", [(-0.128, 0.020, 0.24), (-0.190, 0.020, 0.398)], 0.003, steel, 6))
    parts.append(cylinder("Antenna tip", 0.005, 0.008, (-0.190, 0.020, 0.398), steel, 8))
    for i, radius in enumerate((0.048, 0.078, 0.108)):
        points = [(0.126 + radius * math.cos(a), -0.005, 0.157 + radius * math.sin(a))
                  for a in [(-0.78 + j * 1.56 / 8) for j in range(9)]]
        parts.append(tube(f"Curved sound wave {i + 1}", points, 0.004, gold))
    return parts


def serving_body(name, x0, x1, width, bottom, top, opening, mat):
    """Truck shell with an actual rectangular opening in its negative-Y side."""
    left, right, low, high = opening
    y0, y1 = -width / 2, width / 2
    vertices = [(x0, y0, bottom), (x1, y0, bottom), (x1, y1, bottom), (x0, y1, bottom),
                (x0, y0, top), (x1, y0, top), (x1, y1, top), (x0, y1, top)]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 4, 7, 3), (1, 2, 6, 5), (2, 3, 7, 6)]
    for xa, xb, za, zb in [(x0, left, bottom, top), (right, x1, bottom, top),
                            (left, right, bottom, low), (left, right, high, top)]:
        n = len(vertices)
        vertices += [(xa, y0, za), (xb, y0, za), (xb, y0, zb), (xa, y0, zb)]
        faces.append((n, n + 1, n + 2, n + 3))
    return mesh(name, vertices, faces, [mat])


def build_truck(big=False):
    maroon = material("Truck - maroon enamel", (0.37, 0.045, 0.065), 0.5)
    cream = material("Truck - warm cream", (0.96, 0.85, 0.62), 0.55)
    gold = material("Truck - gold trim", (0.94, 0.57, 0.13), 0.45)
    black = material("Truck - black tyres", (0.035, 0.030, 0.030))
    hub = metal("Truck - wheel hubs", (0.65, 0.62, 0.54))
    glass = material("Truck - blue cab glass", (0.20, 0.43, 0.51), 0.28)
    inside = material("Truck - serving recess", (0.105, 0.055, 0.040))
    lamp = material("Truck - headlights", (1.0, 0.93, 0.67))
    length, width = (0.75, 0.35) if big else (0.60, 0.30)
    front, rear = length / 2, -length / 2
    roof = 0.40 if big else 0.325
    radius = 0.058 if big else 0.050
    parts = [block("Maroon lower truck body", (length, width, 0.142),
                   (0, 0, 0.138), maroon, 0.018),
             block("Black undercarriage", (length * 0.82, width * 0.80, 0.030),
                   (0, 0, 0.077), black)]
    cab_length = 0.205 if big else 0.19
    cab_x = front - cab_length / 2
    window_width = 0.37 if big else 0.285
    window_x = -0.106 if big else -0.080
    window_z = 0.283 if big else 0.250
    window_h = 0.134 if big else 0.086
    opening = (window_x - window_width / 2, window_x + window_width / 2,
               window_z - window_h / 2, window_z + window_h / 2)
    parts.append(serving_body("Open serving body", rear, front - cab_length,
                              width, 0.20, roof, opening, maroon if big else cream))
    parts.append(block("Rounded cream cab upper", (cab_length, width * 0.98, 0.118),
                       (cab_x, 0, 0.259), cream, 0.015))
    for side in (-1, 1):
        y = side * (width / 2 + 0.003)
        parts.append(block("Cab side window", (cab_length * 0.70, 0.004, 0.079),
                           (cab_x - 0.006, y, 0.266), glass, 0.009))
        parts.append(block("Door handle", (0.031, 0.006, 0.005),
                           (cab_x - 0.036, y * 1.02, 0.207), gold))
        for x in (rear + length * 0.20, front - length * 0.19):
            parts.append(cylinder("Black wheel", radius, 0.027, (x, y, radius), black, 12,
                                  (math.pi / 2, 0, 0)))
            parts.append(cylinder("Cream wheel hub", radius * 0.48, 0.029,
                                  (x, y + side * 0.003, radius), hub, 10, (math.pi / 2, 0, 0)))
    parts.append(block("Front windshield", (0.004, width * 0.80, 0.078),
                       (front + 0.001, 0, 0.265), glass, 0.009))
    parts.append(block("Front bumper", (0.018, width * 0.88, 0.021),
                       (front + 0.008, 0, 0.099), hub, 0.005))
    for y in (-width * 0.31, width * 0.31):
        parts.append(block("Warm headlight", (0.008, 0.040, 0.025),
                           (front + 0.008, y, 0.159), lamp, 0.006))
    # Recessed back wall leaves visible depth behind the genuinely open shell.
    y = -width / 2
    parts.append(block("Dark open serving window", (window_width, 0.004, window_h),
                       (window_x, y + 0.030, window_z), inside))
    for x in (window_x - window_width / 2, window_x + window_width / 2):
        parts.append(block("Serving window upright", (0.010, 0.018, window_h + 0.018),
                           (x, y - 0.006, window_z), gold))
    for z in (window_z - window_h / 2, window_z + window_h / 2):
        parts.append(block("Serving window horizontal frame", (window_width + 0.01, 0.018, 0.009),
                           (window_x, y - 0.006, z), gold))
    parts.append(block("Serving counter ledge", (window_width + 0.035, 0.079, 0.011),
                       (window_x, y - 0.030, window_z - window_h / 2), cream))
    # Raised top-hinged hatch forms a striped awning, with a hanging scallop-like lip.
    awning_z = window_z + window_h / 2 + 0.018
    for i in range(6):
        stripe_width = (window_width + 0.036) / 6
        x = window_x + (i - 2.5) * stripe_width
        stripe_mat = cream if i % 2 else maroon
        parts.append(block("Striped open hatch awning", (stripe_width, 0.109, 0.009),
                           (x, y - 0.044, awning_z), stripe_mat, rotation=(-0.13, 0, 0)))
        parts.append(block("Awning valance", (stripe_width, 0.007, 0.025),
                           (x, y - 0.098, awning_z - 0.006), stripe_mat, 0.003))
    if big:
        parts.append(block("Gold belt trim", (0.54, 0.006, 0.012), (-0.105, y - 0.005, 0.173), gold))
        for x in (-0.23, 0.03):
            parts.append(block("Roof sign support", (0.014, 0.016, 0.044), (x, 0, roof + 0.020), gold))
        parts.append(block("Rooftop sign gold border", (0.37, 0.032, 0.101),
                           (-0.10, 0, roof + 0.086), gold, 0.008))
        parts.append(block("Rooftop sign cream inset", (0.345, 0.003, 0.077),
                           (-0.10, -0.018, roof + 0.086), cream, 0.004))
        logo = flame("Rooftop sign flame", maroon)
        logo.scale = (0.70, 1, 0.70)
        parts.append(transform(logo, (-0.10, -0.021, roof + 0.062)))
    return parts


def plate(name, radius, ceramic):
    return lathe(name, [(radius * 0.65, 0), (radius * 0.91, 0.003),
                        (radius, 0.012), (radius, 0.017),
                        (radius * 0.88, 0.018), (radius * 0.70, 0.009)],
                 [ceramic], segments=20)


def almond(name, location, mat, angle=0):
    # Thin pointed almond slice, not a sphere; twelve triangles total.
    obj = silhouette(name, [(-0.013, 0), (-0.007, -0.004), (0.007, -0.004),
                            (0.013, 0), (0.007, 0.004), (-0.007, 0.004)], 0.002, mat)
    return transform(obj, location, (-math.pi / 2, 0, angle))


def build_saffron_cake():
    white = material("Cake - white plate", (0.96, 0.95, 0.90), 0.35)
    milk = material("Cake - saffron milk pool", (1.0, 0.91, 0.68), 0.27)
    sponge = material("Cake - pale yellow sponge", (0.95, 0.76, 0.30))
    topping = material("Cake - soaked cream top", (1.0, 0.89, 0.51), 0.40)
    saffron = material("Cake - orange saffron threads", (0.86, 0.20, 0.025))
    green = material("Cake - crushed pistachio", (0.25, 0.46, 0.075))
    crumb = material("Cake - sponge pores", (0.73, 0.49, 0.15))
    parts = [plate("Small white cake plate", 0.15, white),
             cylinder("Shallow saffron milk pool", 0.119, 0.004, (0, 0, 0.014), milk, 24),
             block("Square saffron sponge slice", (0.158, 0.156, 0.080),
                   (0, 0, 0.056), sponge, 0.004),
             block("Milky cake topping", (0.159, 0.157, 0.008),
                   (0, 0, 0.099), topping, 0.003)]
    rng = random.Random(8701)
    for i in range(6):
        x, y = rng.uniform(-0.045, 0.045), rng.uniform(-0.045, 0.045)
        parts.append(tube(f"Saffron thread {i + 1}", [(x - 0.012, y, 0.104),
                         (x, y + 0.004, 0.105), (x + 0.011, y + 0.002, 0.104)],
                          0.0009, saffron))
    for i in range(13):
        parts.append(fleck(f"Pistachio crumb {i + 1}", rng.uniform(-0.065, 0.065),
                           rng.uniform(-0.063, 0.063), 0.104, rng.uniform(0.002, 0.004), green, rng))
    for i in range(9):
        parts.append(block("Visible sponge pore", (0.003, 0.0006, 0.002),
                           (rng.uniform(-0.065, 0.065), -0.0783, rng.uniform(0.028, 0.083)), crumb))
    return parts


def build_sago_halwa():
    glass = glass_material("Sago - pale glass bowl", (0.66, 0.86, 0.91), 0.28)
    amber = material("Sago - glossy amber orange", (0.88, 0.29, 0.035), 0.20)
    pearl = glass_material("Sago - translucent amber pearls", (1.0, 0.58, 0.16), 0.78)
    almond_mat = material("Sago - ivory almond slices", (1.0, 0.86, 0.60))
    parts = [lathe("Small glass dessert bowl", [(0.065, 0), (0.080, 0.009),
                    (0.130, 0.055), (0.150, 0.086), (0.150, 0.094),
                    (0.143, 0.094), (0.123, 0.058), (0.075, 0.017)], [glass], segments=20),
             dome("Glossy sago halwa dome", 0.130, 0.094, (0, 0, 0.034), amber)]
    for i in range(7):
        a = i * 2.39996
        r = 0.038 + (i % 3) * 0.021
        z = 0.034 + dome_surface(0.130, 0.094, r) - 0.002
        parts.append(dome(f"Visible sago pearl {i + 1}", 0.011, 0.012,
                          (r * math.cos(a), r * math.sin(a), z), pearl, segments=8))
    for i in range(6):
        a = i * 2.39996
        r = 0.018 + (i % 2) * 0.029
        parts.append(almond(f"Sago sliced almond {i + 1}",
                            (r * math.cos(a), r * math.sin(a),
                             0.0355 + dome_surface(0.130, 0.094, r)),
                            almond_mat, a))
    return parts


def build_omani_halwa():
    dish = material("Omani - deep teal traditional dish", (0.055, 0.23, 0.21), 0.38)
    gold = material("Omani - gold dish rim", (0.77, 0.48, 0.15), 0.40)
    halwa = material("Omani - dark brown halwa", (0.20, 0.065, 0.023), 0.24)
    almond_mat = material("Omani - almond slivers", (0.94, 0.81, 0.56))
    cardamom = material("Omani - cardamom sprinkle", (0.28, 0.32, 0.085))
    steel = metal("Omani - tiny brass spoon", (0.72, 0.50, 0.19))
    bowl = lathe("Traditional small round halwa dish", [(0.070, 0), (0.079, 0.008),
                  (0.128, 0.033), (0.139, 0.052), (0.140, 0.059),
                  (0.130, 0.060), (0.116, 0.039), (0.070, 0.018)], [dish, gold], segments=20)
    for polygon in bowl.data.polygons[61:101]:
        polygon.material_index = 1
    parts = [bowl, dome("Dark Omani halwa mound", 0.115, 0.065, (0, 0, 0.026), halwa)]
    for i in range(7):
        a = i * 2.39996
        r = 0.014 + (i % 3) * 0.017
        parts.append(almond(f"Omani almond sliver {i + 1}",
                            (r * math.cos(a), r * math.sin(a),
                             0.0275 + dome_surface(0.115, 0.065, r)), almond_mat, a))
    rng = random.Random(901)
    for i in range(16):
        a, r = rng.uniform(0, TAU), rng.uniform(0.015, 0.070)
        parts.append(fleck(f"Cardamom speck {i + 1}", r * math.cos(a), r * math.sin(a),
                           0.027 + dome_surface(0.115, 0.065, r),
                           0.0017, cardamom, rng))
    spoon = lathe("Tiny spoon bowl", [(0.010, 0), (0.017, 0.004), (0.020, 0.009),
                  (0.017, 0.010), (0.010, 0.005)], [steel], segments=12)
    spoon.scale.y = 0.70
    parts.append(transform(spoon, (0.096, -0.039, 0.055)))
    parts.append(block("Tiny spoon handle", (0.069, 0.007, 0.003),
                       (0.140, -0.039, 0.064), steel, 0.002))
    return parts


def build_sweets_counter():
    wood = material("Counter - walnut wooden base", (0.29, 0.125, 0.050))
    trim = material("Counter - warm wooden trim", (0.58, 0.31, 0.105))
    glass = glass_material("Counter - transparent light blue glass", (0.64, 0.85, 0.94), 0.18)
    steel = metal("Counter - sweet trays", (0.72, 0.71, 0.62))
    colors = [material("Counter - yellow saffron sweets", (0.98, 0.75, 0.22)),
              material("Counter - amber sago sweets", (0.94, 0.33, 0.035), 0.24),
              material("Counter - brown Omani sweets", (0.25, 0.075, 0.025), 0.26)]
    parts = [block("Wooden display plinth", (0.30, 0.188, 0.072), (0, 0, 0.036), wood, 0.005),
             block("Display shelf", (0.304, 0.194, 0.011), (0, 0, 0.077), trim),
             block("Glass case top", (0.30, 0.188, 0.003), (0, 0, 0.218), glass),
             block("Glass case front", (0.30, 0.002, 0.137), (0, -0.094, 0.148), glass),
             block("Glass case back", (0.30, 0.002, 0.137), (0, 0.094, 0.148), glass)]
    for x in (-0.15, 0.15):
        parts.append(block("Glass case side", (0.002, 0.188, 0.137), (x, 0, 0.148), glass))
        for y in (-0.094, 0.094):
            parts.append(block("Display corner post", (0.005, 0.005, 0.143), (x, y, 0.149), trim))
    for i, mat in enumerate(colors):
        x = (i - 1) * 0.096
        parts.append(block(f"Sweet tray {i + 1}", (0.085, 0.151, 0.007), (x, 0, 0.087), steel, 0.004))
        for row in (-1, 0, 1):
            parts.append(dome(f"Tray {i + 1} sweet mound {row + 2}", 0.031, 0.028,
                              (x, row * 0.044, 0.091), mat, segments=8))
    for x in (-0.080, 0, 0.080):
        parts.append(block("Wood base inset stripe", (0.003, 0.001, 0.038),
                           (x, -0.0945, 0.033), trim))
    return parts


def export_asset(parts, name, destination, nominal_width):
    """Join, ground and centre the mesh; verify the strict per-icon budget."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        assert obj.type == "MESH", f"{name}: non-mesh part {obj.name}"
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    vertices = obj.data.vertices
    lower = Vector(tuple(min(v.co[i] for v in vertices) for i in range(3)))
    upper = Vector(tuple(max(v.co[i] for v in vertices) for i in range(3)))
    offset = Vector(((lower.x + upper.x) / 2, (lower.y + upper.y) / 2, lower.z))
    for vertex in vertices:
        vertex.co -= offset
    obj.data.update()
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.view_layer.update()
    obj.data.calc_loop_triangles()
    triangles = len(obj.data.loop_triangles)
    assert 0 < triangles < 1500, f"{name}: {triangles} triangles exceeds budget"
    assert all(math.isfinite(c) for v in vertices for c in v.co), name
    assert abs(min(v.co.z for v in vertices)) < 0.00001, f"{name}: base off floor"
    assert obj.location.length < 0.00001, f"{name}: origin is not base centre"
    assert nominal_width * 0.75 <= obj.dimensions.x <= nominal_width * 1.20, (
        f"{name}: unexpected width {obj.dimensions.x:.3f}")
    assert all(not node.type.startswith("TEX_") for slot in obj.material_slots
               for node in slot.material.node_tree.nodes), f"{name}: texture found"
    print(f"{name}: {triangles} triangles; dimensions "
          f"{obj.dimensions.x:.3f} x {obj.dimensions.y:.3f} x {obj.dimensions.z:.3f} m",
          flush=True)
    bpy.ops.export_scene.gltf(filepath=str(destination / f"{name}.glb"),
                              export_format="GLB", export_apply=True,
                              export_yup=True, use_selection=True,
                              export_cameras=False, export_lights=False)
    return obj


def main():
    for directory in (ICONS, FOOD, PREVIEWS):
        directory.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    assets = []
    for builder, name, destination, width in [
            (build_fliers, "fliers", ICONS, 0.40),
            (build_posters, "posters", ICONS, 0.40),
            (build_social, "social", ICONS, 0.40),
            (build_radio, "radio", ICONS, 0.40),
            (build_truck, "truck", ICONS, 0.60),
            (lambda: build_truck(big=True), "truck-big", ICONS, 0.75),
            (build_saffron_cake, "saffron-cake", FOOD, 0.30),
            (build_sago_halwa, "sago-halwa", FOOD, 0.30),
            (build_omani_halwa, "omani-halwa", FOOD, 0.30),
            (build_sweets_counter, "sweets-counter", FOOD, 0.30)]:
        assets.append((export_asset(builder(), name, destination, width), name))
    print("Finished all ten GLB exports.", flush=True)
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--no-previews" not in arguments:
        for obj, _ in assets:
            obj.hide_render = True
        for obj, name in assets:
            obj.hide_render = False
            preview(obj, f"iconb_{name}_preview.png")
            obj.hide_render = True
        for obj, _ in assets:
            obj.hide_render = False
        print("Finished all ten 512 x 512 EEVEE previews.", flush=True)


if __name__ == "__main__":
    main()
