"""Builds the lightning gun: the Orb Claw, a plasma globe on a compact body with three claws reaching past it.

Run from the project root (Blender 5.1 or newer):
    blender --background --factory-startup --python tools/assetgen/lightning_gun.py -- [--preview-dir DIR] [--no-preview]

Writes:
    art/blender/lightning_gun.blend          the source file (rebuilt from scratch every run, so hand edits are lost)
    models/lightning_gun/lightning_gun.glb   what Godot uses (scenes/weapons/lightning_gun.tscn)
    DIR/lightning_gun_*.png                  preview renders (default art/blender/previews)

Designed for the first-person view, where the gun sits low on the right and you see its top and left side:
it is short (no stock), the orb rides high in the middle of the body with its cage open on the left (close enough
that it sits below the claws on screen instead of hiding them), three glass tubes stick out flat from the left
flank over a glowing seam, a charge gauge sits on top at the back, and the claws are big and spread so their
glowing tips frame the crosshair.

Modelled about 0.75 m long with the barrel along +Y; Godot scales it into the weapon slot. Nodes in the glTF:
    Body          every fixed part, one mesh with several materials
    OrbGlass      the glass globe                         OrbCore   its glowing core
    Claw0..Claw2  the claws, each with its origin at its hinge and its local X along the hinge, so rotating one
                  about its own X swings it outwards (positive) or inwards
    Tip0..Tip2    empties on the claws' glowing tips (children of the claws), where their arcs start
    Orb, Muzzle   empties: the globe's centre (for its light and arcs) and the point between the claw tips where the
                  lightning leaves
    Tube0Start..Tube2End
                  empties at the two ends of each glass tube, for the arcs rattling inside them
The arcs are drawn by the game, not modelled; the previews add a few so the renders read.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "lightning_gun.blend")
GLB_PATH = os.path.join(ROOT, "models", "lightning_gun", "lightning_gun.glb")

ELECTRIC = (0.15, 0.45, 1.0)
METAL = (0.09, 0.1, 0.14)
METAL_LIGHT = (0.22, 0.24, 0.3)
COPPER = (0.85, 0.42, 0.18)

ORB_CENTRE = Vector((0.0, 0.05, 0.1))
ORB_RADIUS = 0.085
AXIS_Z = 0.04                       # height of the claws' axis
CLAW_BASE_Y = 0.3
CLAW_LENGTH = 0.36
CLAW_ANGLES = (35.0, 145.0, 270.0)  # round the barrel, seen from behind: upper right, upper left, bottom
MUZZLE = Vector((0.0, CLAW_BASE_Y + CLAW_LENGTH + 0.02, AXIS_Z))

# The glass tubes on the left flank: three in a row along the gun, each lying flat and sticking straight out
# sideways from a socket in the body. (start, end): start at the body, end at the tube's outer tip.
TUBE_RADIUS = 0.021
TUBES = [(Vector((-0.075, y, 0.03)), Vector((-0.19, y, 0.03))) for y in (-0.11, -0.04, 0.03)]


def v(*a):
    return Vector(a)


# ------------------------------------------------------------------------------------------------------ materials

def _nodes(mat):
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    return mat.node_tree.nodes


def surface(name, colour, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    b = _nodes(mat).get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return mat


def glow(name, colour, strength):
    mat = surface(name, colour)
    b = mat.node_tree.nodes.get("Principled BSDF")
    b.inputs["Emission Color"].default_value = (*colour, 1.0)
    b.inputs["Emission Strength"].default_value = strength
    return mat


def glass(name, colour, alpha):
    mat = surface(name, colour, 0.0, 0.05)
    b = mat.node_tree.nodes.get("Principled BSDF")
    b.inputs["Alpha"].default_value = alpha
    b.inputs["Emission Color"].default_value = (*colour, 1.0)
    b.inputs["Emission Strength"].default_value = 0.3
    try:
        mat.surface_render_method = "BLENDED"
    except AttributeError:
        mat.blend_method = "BLEND"
    mat.use_backface_culling = False
    return mat


# ---------------------------------------------------------------------------------------------------------- shapes

class Mesh:
    """Geometry for one object, kept per material, joined into one mesh with a slot per material."""

    def __init__(self):
        self.parts = {}

    def bm(self, material):
        if material not in self.parts:
            self.parts[material] = bmesh.new()
        return self.parts[material]

    def make(self, name, mats, coll, location=(0, 0, 0)):
        me = bpy.data.meshes.new(name)
        merged = bmesh.new()
        for index, (key, bm) in enumerate(self.parts.items()):
            tmp = bpy.data.meshes.new("tmp")
            bm.to_mesh(tmp)
            for poly in tmp.polygons:
                poly.material_index = index
            merged.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
            me.materials.append(mats[key])
            bm.free()
        bmesh.ops.recalc_face_normals(merged, faces=merged.faces)
        merged.to_mesh(me)
        merged.free()
        ob = bpy.data.objects.new(name, me)
        ob.location = location
        coll.objects.link(ob)
        return ob


def box(bm, centre, size, rot=None):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=v(*size), verts=ret["verts"])
    if rot:
        bmesh.ops.rotate(bm, verts=ret["verts"], cent=v(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=ret["verts"], vec=v(*centre))


def tube(bm, p0, p1, r0, r1=None, segments=10):
    """A capped cylinder (or cone) from point p0 to p1."""
    r1 = r0 if r1 is None else r1
    p0, p1 = v(*p0), v(*p1)
    axis = p1 - p0
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r0, radius2=r1, depth=axis.length)
    rot = axis.normalized().to_track_quat("Z", "Y").to_matrix()
    bmesh.ops.rotate(bm, verts=ret["verts"], cent=v(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=ret["verts"], vec=(p0 + p1) / 2)


def torus(bm, centre, axis, major, minor, segments=16, sides=6, arc=1.0, start=0.0):
    """A ring (or part of one, `arc` of the way round from `start` radians) round `axis` through `centre`."""
    axis = v(*axis).normalized()
    rot = axis.to_track_quat("Z", "Y").to_matrix()
    closed = arc >= 1.0
    count = segments if closed else segments + 1
    rings = []
    for i in range(count):
        a = start + math.tau * arc * i / segments
        ring = []
        for j in range(sides):
            b = math.tau * j / sides
            r = major + math.cos(b) * minor
            ring.append(bm.verts.new(rot @ v(math.cos(a) * r, math.sin(a) * r, math.sin(b) * minor) + v(*centre)))
        rings.append(ring)
    for i in range(segments):
        a, b = rings[i], rings[(i + 1) % count]
        for j in range(sides):
            bm.faces.new([a[j], b[j], b[(j + 1) % sides], a[(j + 1) % sides]])
    if not closed:
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])


def ball(bm, centre, radius, segs=8):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs // 2), radius=radius)
    bmesh.ops.translate(bm, verts=ret["verts"], vec=v(*centre))


def bolt(bm, p0, p1, rng, kinks=6, jitter=0.25, radius=0.004):
    """A jagged arc of lightning from p0 to p1, made of thin tubes (previews only)."""
    p0, p1 = v(*p0), v(*p1)
    span = p1 - p0
    side = span.orthogonal().normalized()
    up = span.cross(side).normalized()
    points = [p0]
    for k in range(1, kinks):
        t = k / kinks
        wiggle = span.length * jitter * math.sin(math.pi * t)
        points.append(p0 + span * t + side * rng.uniform(-1, 1) * wiggle + up * rng.uniform(-1, 1) * wiggle)
    points.append(p1)
    for a, b in zip(points, points[1:]):
        tube(bm, a, b, radius, radius, 5)


# ------------------------------------------------------------------------------------------------------------ gun

def claw_radial(angle_deg):
    a = math.radians(angle_deg)
    return v(math.cos(a), 0.0, math.sin(a))


def claw_profile():
    """Points along a claw in its own space: base at the origin, reaching along +Y, bulging out along +Z."""
    pts = []
    for k in range(7):
        t = k / 6
        out = 0.1 * math.sin(math.pi * t * 0.85) - 0.03 * t
        pts.append(v(0.0, CLAW_LENGTH * t, out))
    return pts


def build_body(coll):
    m = Mesh()
    metal, light, copper, glowing = m.bm("metal"), m.bm("metal_light"), m.bm("copper"), m.bm("glow")

    # compact body: no stock, a short coil pack at the back
    box(metal, (0, 0.0, -0.02), (0.15, 0.34, 0.13))
    box(light, (0, 0.0, 0.05), (0.12, 0.3, 0.02))                          # top deck
    box(metal, (0, -0.04, -0.13), (0.045, 0.065, 0.14), Matrix.Rotation(math.radians(-18), 3, "X"))  # grip
    box(metal, (0, 0.02, -0.095), (0.012, 0.08, 0.01))                     # trigger guard
    box(light, (0, 0.012, -0.08), (0.008, 0.012, 0.03))                    # trigger
    tube(copper, (0, -0.21, -0.01), (0, -0.16, -0.01), 0.058, 0.058, 14)   # coil pack
    tube(metal, (0, -0.225, -0.01), (0, -0.208, -0.01), 0.062, 0.062, 14)

    # the orb sits high: a ring mount under it and three ribs over its right side, open on the left
    torus(light, ORB_CENTRE - v(0, 0, ORB_RADIUS * 0.55), (0, 0, 1), ORB_RADIUS * 0.85, 0.012, 18, 6)
    for k in range(3):
        y = ORB_CENTRE.y + (k - 1) * 0.055
        r = math.sqrt(max(ORB_RADIUS ** 2 - (y - ORB_CENTRE.y) ** 2, 0.0)) + 0.012
        start = len(metal.verts)
        torus(metal, v(0, y, ORB_CENTRE.z), (0, 1, 0), r, 0.008, 12, 5, 0.5, 0.0)
        metal.verts.ensure_lookup_table()
        rib = metal.verts[start:]
        if sum(vert.co.x for vert in rib) < 0:     # keep the ribs on the right: the left stays open towards you
            for vert in rib:
                vert.co.x = -vert.co.x
            bmesh.ops.reverse_faces(metal, faces=list({f for vert in rib for f in vert.link_faces}))

    # front collar the claws grow from, round the barrel axis
    box(light, (0, CLAW_BASE_Y - 0.02, AXIS_Z), (0.13, 0.05, 0.13))
    tube(metal, (0, CLAW_BASE_Y, AXIS_Z), (0, CLAW_BASE_Y + 0.05, AXIS_Z), 0.03, 0.022, 10)   # emitter nose
    box(metal, (0, 0.24, AXIS_Z - 0.01), (0.1, 0.1, 0.09))                 # neck between body and collar

    # left flank, the side that faces the middle of the screen: glass tubes sticking out sideways (the game fills
    # them with rattling arcs), a glowing seam under them, a cable
    for start, end in TUBES:
        out = (end - start).normalized()
        tube(light, start - out * 0.004, start + out * 0.014, TUBE_RADIUS + 0.007, TUBE_RADIUS + 0.005, 12)  # socket
        tube(m.bm("glass"), start + out * 0.01, end, TUBE_RADIUS, TUBE_RADIUS, 12)
        tube(copper, end - out * 0.01, end + out * 0.01, TUBE_RADIUS + 0.004, TUBE_RADIUS + 0.004, 12)  # end cap
        ball(copper, end + out * 0.012, 0.007, 6)                         # terminal nub
    box(glowing, (-0.0765, 0.0, -0.072), (0.004, 0.3, 0.008))              # seam
    path = [v(-0.06, -0.17, 0.0), v(-0.085, -0.1, 0.06), v(-0.075, ORB_CENTRE.y - 0.02, 0.07)]
    for a, b in zip(path, path[1:]):
        tube(metal, a, b, 0.011, 0.011, 8)

    # charge gauge on top at the back, right under your eye
    box(metal, (0, -0.125, 0.064), (0.06, 0.07, 0.01))
    for k in range(4):
        box(glowing, (0, -0.15 + k * 0.017, 0.07), (0.04, 0.01, 0.004))

    return m.make("Body", MATS, coll)


def build_orb(coll):
    g = Mesh()
    ball(g.bm("glass"), (0, 0, 0), ORB_RADIUS, 16)
    glass_ob = g.make("OrbGlass", MATS, coll, ORB_CENTRE)
    c = Mesh()
    ball(c.bm("glow"), (0, 0, 0), 0.024, 8)
    core = c.make("OrbCore", MATS, coll, ORB_CENTRE)
    return glass_ob, core


def build_claws(coll):
    claws = []
    pts = claw_profile()
    for i, angle in enumerate(CLAW_ANGLES):
        m = Mesh()
        for j, (q0, q1) in enumerate(zip(pts, pts[1:])):
            tube(m.bm("metal" if j < 3 else "copper"), q0, q1, 0.019 - j * 0.0022, 0.017 - j * 0.0022, 8)
        box(m.bm("metal_light"), (0, 0.04, 0.02), (0.03, 0.05, 0.02))     # knuckle plate
        ball(m.bm("glow"), pts[-1], 0.02, 8)
        radial = claw_radial(angle)
        base = v(0, CLAW_BASE_Y, AXIS_Z) + radial * 0.055
        ob = m.make(f"Claw{i}", MATS, coll, base)
        ob.rotation_euler = (0.0, math.atan2(radial.x, radial.z), 0.0)     # local +Z points out along `radial`
        tip = bpy.data.objects.new(f"Tip{i}", None)                        # where the claw's arcs start
        tip.parent = ob
        tip.location = pts[-1]
        tip.empty_display_size = 0.02
        coll.objects.link(tip)
        claws.append(ob)
    return claws


def build_markers(coll):
    markers = [("Orb", ORB_CENTRE), ("Muzzle", MUZZLE)]
    for i, (start, end) in enumerate(TUBES):
        markers += [(f"Tube{i}Start", start), (f"Tube{i}End", end)]
    for name, at in markers:
        empty = bpy.data.objects.new(name, None)
        empty.location = at
        empty.empty_display_size = 0.03
        coll.objects.link(empty)


def build_preview_arcs(coll, claws, rng):
    m = Mesh()
    for _ in range(6):
        d = v(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)).normalized()
        bolt(m.bm("arc"), ORB_CENTRE + d * 0.024, ORB_CENTRE + d * (ORB_RADIUS - 0.006), rng, 4, 0.35, 0.0025)
    bpy.context.view_layer.update()
    for start, end in TUBES:
        bolt(m.bm("arc"), start, end, rng, 7, 0.04, 0.0025)
    tip_local = claw_profile()[-1]
    for claw in claws:
        bolt(m.bm("arc"), claw.matrix_world @ tip_local, MUZZLE, rng, 4, 0.3, 0.003)
    return m.make("PreviewArcs", MATS, coll)


# --------------------------------------------------------------------------------------------------------- preview

def build_preview_scene():
    scene = bpy.context.scene
    coll = bpy.data.collections.new("Preview")
    scene.collection.children.link(coll)
    world = bpy.data.worlds.new("Synthwave")
    _nodes(world)
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.0, 0.07, 1.0)
    scene.world = world
    for name, energy, colour, rot in (("PreviewKey", 3.5, (1.0, 0.85, 0.9), (50, 0, -35)),
                                      ("PreviewFill", 1.5, (0.4, 0.8, 1.0), (110, 0, 150))):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = energy
        light.color = colour
        ob = bpy.data.objects.new(name, light)
        ob.rotation_euler = [math.radians(r) for r in rot]
        coll.objects.link(ob)
    orb_light = bpy.data.lights.new("PreviewOrbLight", "POINT")             # what the game's orb light does
    orb_light.energy = 6.0
    orb_light.color = ELECTRIC
    orb_light.shadow_soft_size = 0.02
    ob = bpy.data.objects.new("PreviewOrbLight", orb_light)
    ob.location = ORB_CENTRE
    coll.objects.link(ob)
    cam = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    coll.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 32
    scene.view_settings.view_transform = "Standard"
    return cam, ob


def render(cam, path, location, target, lens=50, size=(1000, 800)):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    cam.data.sensor_fit = "AUTO"
    cam.location = location
    cam.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def held_view(cam, path, coll, orb_light):
    """Roughly the game's first-person view: a 90 degree vertical field of view like the player camera, the gun low
    on the right. The real position is tuned in Godot."""
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1244, 700
    rig = bpy.data.objects.new("HeldRig", None)
    coll.objects.link(rig)
    moved = [o for o in coll.objects if o is not rig and o.parent is None] + [orb_light]
    for o in moved:
        o.parent = rig
    rig.location = (0.27, 0.4, -0.3)
    rig.rotation_euler = (math.radians(7), math.radians(-8), math.radians(2))
    cam.location = (0, 0, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(90)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)
    bpy.context.view_layer.update()
    for o in moved:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.data.objects.remove(rig)
    bpy.context.view_layer.update()


def previews(out_dir, coll):
    os.makedirs(out_dir, exist_ok=True)
    cam, orb_light = build_preview_scene()
    render(cam, os.path.join(out_dir, "lightning_gun_side.png"), v(-1.6, 0.2, 0.05), v(0, 0.2, 0.0), 50)
    render(cam, os.path.join(out_dir, "lightning_gun_angle.png"), v(-0.95, 1.2, 0.5), v(0, 0.18, 0.0), 45)
    render(cam, os.path.join(out_dir, "lightning_gun_back.png"), v(-0.55, -0.9, 0.45), v(0, 0.2, 0.0), 40)
    held_view(cam, os.path.join(out_dir, "lightning_gun_held.png"), coll, orb_light)


# ---------------------------------------------------------------------------------------------------------- export

def export_glb(coll, arcs):
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.objects:
        o.select_set(o is not arcs)
    bpy.context.view_layer.objects.active = coll.objects["Body"]
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False)
    print("exported", GLB_PATH)


# ------------------------------------------------------------------------------------------------------------ main

MATS = {}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview_dir = os.path.join(ROOT, "art", "blender", "previews")
    if "--preview-dir" in argv:
        preview_dir = argv[argv.index("--preview-dir") + 1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.update({
        "metal": surface("Metal", METAL, 0.7, 0.4),
        "metal_light": surface("MetalLight", METAL_LIGHT, 0.8, 0.3),
        "copper": surface("Copper", COPPER, 0.9, 0.3),
        "glass": glass("Glass", (0.5, 0.75, 1.0), 0.2),
        "glow": glow("Glow", ELECTRIC, 1.6),
        "arc": glow("Arc", (0.2, 0.5, 1.0), 1.3),
    })
    rng = random.Random(5)
    coll = bpy.data.collections.new("LightningGun")
    bpy.context.scene.collection.children.link(coll)
    build_body(coll)
    build_orb(coll)
    claws = build_claws(coll)
    build_markers(coll)
    arcs = build_preview_arcs(coll, claws, rng)

    if "--no-preview" not in argv:
        previews(preview_dir, coll)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("saved", BLEND_PATH)
    export_glb(coll, arcs)


main()
