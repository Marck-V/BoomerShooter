"""Builds the hand boss: a giant, low-poly, faceted right hand with a rig and a few poses.

Run from the project root (Blender 5.1 or newer):
    blender --background --factory-startup --python tools/assetgen/hand_boss.py -- [--preview-dir DIR] [--no-preview]

Writes:
    art/blender/hand.blend           the source file (rebuilt from scratch every run, so hand edits there are lost)
    models/hand_boss/hand_boss.glb   what Godot uses: one skinned mesh, the rig and the poses as animations
    DIR/*.png                        preview renders (default art/blender/previews)

The colours are vertex colours. Godot's glTF importer doesn't switch them on, so hand_boss.glb.import swaps the
material for models/hand_boss/hand_boss_material.tres (and loops Idle). Re-exporting keeps those import settings.

How it's built: each finger, the thumb and the palm with the forearm are separate shells. Each shell is a few
convex hulls (capsules between the joints, bumps on the knuckles) melted together with a voxel remesh, smoothed,
then decimated down to a few hundred triangles, which gives the crystalline facets. Keeping them separate means a
finger's weights can only come from its own bones, so fingers never drag their neighbours when they curl.

Rest pose: palm facing down, fingers pointing along +Y in Blender (forward, -Z, in Godot), forearm behind.
Every bone's local X is its bend axis: a negative X rotation curls a finger towards the palm.
Positions below are in hand units (wrist to middle fingertip is about 0.9); SCALE turns them into meters.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "hand.blend")
GLB_PATH = os.path.join(ROOT, "models", "hand_boss", "hand_boss.glb")
SCALE = 6.0  # wrist to middle fingertip is about 5.4 m, the forearm another 3.9 m
SEED = 7


def v(*a):
    return Vector(a)


# ---------------------------------------------------------------------------------------------------------- layout

# name, knuckle, direction, segment lengths, radii at (knuckle, first joint, second joint, tip)
FINGERS = [
    ("index", v(-0.138, 0.43, 0.005), v(-0.10, 1, 0), (0.20, 0.12, 0.085), (0.052, 0.047, 0.041, 0.033)),
    ("middle", v(-0.045, 0.45, 0.010), v(-0.01, 1, 0), (0.22, 0.13, 0.090), (0.053, 0.048, 0.042, 0.034)),
    ("ring", v(0.048, 0.44, 0.005), v(0.08, 1, 0), (0.205, 0.125, 0.088), (0.049, 0.044, 0.039, 0.031)),
    ("pinky", v(0.138, 0.40, -0.005), v(0.19, 1, 0), (0.16, 0.095, 0.080), (0.043, 0.038, 0.034, 0.027)),
]
THUMB_BASE = v(-0.085, 0.06, -0.02)
THUMB_META_END = v(-0.20, 0.19, -0.035)
THUMB_DIR = v(-0.5, 0.85, -0.05)
THUMB_LENGTHS = (0.12, 0.095)
THUMB_RADII = (0.066, 0.056, 0.049, 0.038)
THUMB_UP = v(-0.6, 0.0, 0.8)  # the way the thumbnail faces
FINGER_UP = v(0, 0, 1)
FLATTEN = 0.85  # fingers are a bit wider than they are tall

ELBOW = v(0, -0.65, 0)
WRIST = v(0, 0, 0)
# Forearm and wrist cross-sections: (y, width radius, height radius, height offset)
ARM_SECTIONS = [(-0.65, 0.17, 0.13, 0.0), (-0.35, 0.15, 0.10, 0.0), (0.0, 0.125, 0.07, 0.0)]


def finger_joints(knuckle, direction, lengths):
    d = direction.normalized()
    joints = [knuckle.copy()]
    for length in lengths:
        joints.append(joints[-1] + d * length)
    return joints


def thumb_joints():
    d = THUMB_DIR.normalized()
    j = [THUMB_BASE.copy(), THUMB_META_END.copy()]
    for length in THUMB_LENGTHS:
        j.append(j[-1] + d * length)
    return j


def frame(direction, up):
    d = direction.normalized()
    u = (up - d * up.dot(d)).normalized()
    side = d.cross(u)
    return side, d, u


# ------------------------------------------------------------------------------------------------------- geometry

def sphere_dirs(n):
    """Evenly spread unit directions (a Fibonacci sphere)."""
    out = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(1 - y * y)
        out.append(v(math.cos(golden * i) * r, y, math.sin(golden * i) * r))
    return out


DIRS = sphere_dirs(48)


def blob(center, radius, side, fwd, up, flatten=FLATTEN):
    return [center + side * d.x * radius + fwd * d.y * radius + up * d.z * radius * flatten for d in DIRS]


def ellipse(center, rx, rz, n=20):
    return [center + v(math.cos(a) * rx, 0, math.sin(a) * rz) for a in (2 * math.pi * i / n for i in range(n))]


def add_hull(bm, points):
    verts = [bm.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(bm, input=verts)
    junk = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    bmesh.ops.delete(bm, geom=junk, context="VERTS")


def bake(obj):
    """Applies the object's modifiers into its mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    obj.modifiers.clear()
    obj.data = new
    bpy.data.meshes.remove(old)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def remesh(obj, voxel, smooth_iterations):
    rem = obj.modifiers.new("remesh", "REMESH")
    rem.mode = "VOXEL"
    rem.voxel_size = voxel
    rem.adaptivity = 0.0
    if smooth_iterations:
        smo = obj.modifiers.new("smooth", "SMOOTH")
        smo.factor = 0.5
        smo.iterations = smooth_iterations
    bake(obj)


def build_shell(name, hulls, facet, jitter, rng):
    """facet: roughly how big the finished facets are, in hand units. None keeps the hulls as they are."""
    bm = bmesh.new()
    for pts in hulls:
        add_hull(bm, pts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)

    if facet:
        remesh(obj, facet * 0.25, 6)  # melt the hulls into one smooth surface
        remesh(obj, facet * 0.8, 0)  # then rebuild it from even, facet-sized quads
        dec = obj.modifiers.new("decimate", "DECIMATE")  # and break up the grid
        dec.ratio = 0.6
        dec.use_collapse_triangulate = True
        bake(obj)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    if jitter:
        bm.normal_update()
        for vert in bm.verts:  # uneven facets, like cut crystal
            vert.co += vert.normal * rng.uniform(-jitter, jitter)
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def assign_weights(obj, segments):
    """Weights each vertex to the nearby bone segments, falling off sharply, so joints blend over about a
    finger's width. segments: (bone name, head, tail)."""
    groups = {}
    for bone_name, _, _ in segments:
        if bone_name not in groups:
            groups[bone_name] = obj.vertex_groups.new(name=bone_name)
    for vert in obj.data.vertices:
        raw = {}
        for bone_name, a, b in segments:
            w = 1.0 / (seg_dist(vert.co, a, b) ** 2 + 1e-7) ** 4
            raw[bone_name] = max(raw.get(bone_name, 0.0), w)
        total = sum(raw.values())
        for bone_name, w in raw.items():
            w /= total
            if w > 0.01:
                groups[bone_name].add([vert.index], w, "REPLACE")


# ---------------------------------------------------------------------------------------------------------- colour

INDIGO = v(0.06, 0.04, 0.32)
VIOLET = v(0.22, 0.06, 0.62)
BLUE = v(0.08, 0.14, 0.70)
TEAL = v(0.02, 0.45, 0.45)
GREEN = v(0.04, 0.50, 0.24)
NAIL = v(0.10, 0.015, 0.20)
NAIL_EDGE = v(0.035, 0.0, 0.08)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def body_colour(p, rng):
    base = lerp(INDIGO, VIOLET, smoothstep(-0.4, 0.5, noise.noise(p * 9.0 + v(3.1, 0.7, 5.2))))
    base = lerp(base, BLUE, 0.5 * smoothstep(0.1, 0.6, noise.noise(p * 5.0 + v(8.0, 1.0, 2.0))))
    patch = smoothstep(0.05, 0.30, noise.noise(p * 6.0 + v(1.7, 4.4, 9.9)))  # the teal-green patches
    tint = lerp(TEAL, GREEN, smoothstep(-0.3, 0.3, noise.noise(p * 7.0 + v(5.5, 2.2, 0.3))))
    c = lerp(base, tint, patch)
    c = c * rng.uniform(0.55, 1.45)  # every facet catches the light a bit differently
    if rng.random() < 0.05:
        c = c * 2.2  # glints
    return c


def paint(obj, colour_fn, rng):
    me = obj.data
    attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in me.polygons:
        c = colour_fn(poly.center, poly.normal, rng)
        col = (min(c.x, 1.0), min(c.y, 1.0), min(c.z, 1.0), 1.0)
        for li in poly.loop_indices:
            attr.data[li].color = col


# ------------------------------------------------------------------------------------------------------- the hand

def finger_hulls(joints, radii, up):
    hulls = []
    for i in range(len(joints) - 1):
        side, fwd, u = frame(joints[i + 1] - joints[i], up)
        hulls.append(blob(joints[i], radii[i], side, fwd, u) + blob(joints[i + 1], radii[i + 1], side, fwd, u))
        # A bony bump over the joint, on the back of the finger
        hulls.append(blob(joints[i] + u * radii[i] * 0.45, radii[i] * 0.62, side, fwd, u, 1.0))
    return hulls


def nail_hull(joints, radii, up):
    a, b = joints[-2], joints[-1]
    side, fwd, u = frame(b - a, up)
    r = radii[-1]
    pts = []
    for t, width, lift in ((0.30, 0.55, 0.92), (0.60, 0.78, 0.96), (0.95, 0.80, 0.92), (1.22, 0.62, 0.55)):
        centre = lerp(a, b, t)
        for s in (-1.0, -0.5, 0.0, 0.5, 1.0):
            top = r * FLATTEN * lift + r * 0.24 * (1 - 0.6 * s * s)
            for h in (top, r * FLATTEN * lift - r * 0.08):
                pts.append(centre + side * s * width * r + u * h)
    return pts


def build_mesh(rng):
    shells = []

    # Palm, wrist and forearm
    hulls = []
    for (y0, rx0, rz0, z0), (y1, rx1, rz1, z1) in zip(ARM_SECTIONS, ARM_SECTIONS[1:]):
        hulls.append(ellipse(v(0, y0, z0), rx0, rz0) + ellipse(v(0, y1, z1), rx1, rz1))
    palm = ellipse(v(0, 0.0, 0.0), 0.125, 0.07) + ellipse(v(-0.005, 0.22, -0.004), 0.185, 0.072)
    for _, knuckle, direction, _, radii in FINGERS:
        side, fwd, u = frame(direction, FINGER_UP)
        palm += blob(knuckle - fwd * 0.015, radii[0] * 1.08, side, fwd, u)
    hulls.append(palm)
    obj = build_shell("palm", hulls, 0.045, 0.006, rng)
    assign_weights(obj, [("forearm", ELBOW, WRIST), ("hand", WRIST, FINGERS[1][1])])
    paint(obj, lambda p, n, r: body_colour(p, r), rng)
    shells.append(obj)

    nails = []
    for name, knuckle, direction, lengths, radii in FINGERS:
        joints = finger_joints(knuckle, direction, lengths)
        obj = build_shell(name, finger_hulls(joints, radii, FINGER_UP), 0.024, 0.003, rng)
        segs = [("hand", knuckle - direction.normalized() * 0.25, knuckle)]
        segs += [(f"{name}_{i + 1}", joints[i], joints[i + 1]) for i in range(3)]
        assign_weights(obj, segs)
        paint(obj, lambda p, n, r: body_colour(p, r), rng)
        shells.append(obj)
        nails.append((name, joints, radii, FINGER_UP))

    joints = thumb_joints()
    hulls = finger_hulls(joints, THUMB_RADII, THUMB_UP)
    side, fwd, u = frame(joints[1] - joints[0], THUMB_UP)
    hulls.append(blob(lerp(joints[0], joints[1], 0.45) - u * 0.02, 0.06, side, fwd, u))  # the ball of the thumb
    obj = build_shell("thumb", hulls, 0.028, 0.0035, rng)
    segs = [("hand", v(-0.02, 0.0, 0.0), joints[0])]
    segs += [(f"thumb_{i}", joints[i], joints[i + 1]) for i in range(3)]
    assign_weights(obj, segs)
    paint(obj, lambda p, n, r: body_colour(p, r), rng)
    shells.append(obj)
    nails.append(("thumb", joints, THUMB_RADII, THUMB_UP))

    for name, joints, radii, up in nails:
        obj = build_shell(f"{name}_nail", [nail_hull(joints, radii, up)], None, 0.0, rng)
        distal = f"{name}_3" if name != "thumb" else "thumb_2"
        obj.vertex_groups.new(name=distal).add([vt.index for vt in obj.data.vertices], 1.0, "REPLACE")
        nail_up = frame(joints[-1] - joints[-2], up)[2]

        def nail_colour(p, n, r, nail_up=nail_up):
            facing = n.dot(nail_up)
            return lerp(NAIL_EDGE, NAIL, smoothstep(0.2, 0.8, facing)) * r.uniform(0.9, 1.1)

        paint(obj, nail_colour, rng)
        shells.append(obj)

    for o in bpy.data.objects:
        o.select_set(False)
    for o in shells:
        o.select_set(True)
    bpy.context.view_layer.objects.active = shells[0]
    bpy.ops.object.join()
    body = shells[0]
    body.name = "HandBossMesh"
    body.data.name = "HandBossMesh"
    body.data.transform(Matrix.Scale(SCALE, 4))
    return body


def build_material():
    mat = bpy.data.materials.new("HandBoss")
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    col = nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mat.node_tree.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.35
    bsdf.inputs["Roughness"].default_value = 0.32
    return mat


def build_rig():
    arm = bpy.data.armatures.new("HandBossRig")
    rig = bpy.data.objects.new("HandBoss", arm)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.data.objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name, head, tail, parent=None, up=FINGER_UP):
        eb = arm.edit_bones.new(name)
        eb.head = head * SCALE
        eb.tail = tail * SCALE
        eb.align_roll(up)
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = (eb.parent.tail - eb.head).length < 1e-4
        return eb

    bone("forearm", ELBOW, WRIST)
    bone("hand", WRIST, FINGERS[1][1], "forearm")
    for name, knuckle, direction, lengths, _ in FINGERS:
        joints = finger_joints(knuckle, direction, lengths)
        parent = "hand"
        for i in range(3):
            bone(f"{name}_{i + 1}", joints[i], joints[i + 1], parent)
            parent = f"{name}_{i + 1}"
    joints = thumb_joints()
    parent = "hand"
    for i in range(3):
        bone(f"thumb_{i}", joints[i], joints[i + 1], parent, THUMB_UP)
        parent = f"thumb_{i}"
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
    return rig


# ----------------------------------------------------------------------------------------------------------- poses
# A pose maps bone names to (x, y, z) rotations in degrees; bones left out are straight. Negative X curls a finger
# towards the palm, positive X bends it back. Z swings a finger sideways: positive towards the thumb.
# The clips only move the fingers and the wrist. Godot moves the whole hand through the arena.

FINGER_NAMES = ("index", "middle", "ring", "pinky")
FINGER_BONES = [f"{f}_{i}" for f in FINGER_NAMES for i in (1, 2, 3)] + ["thumb_0", "thumb_1", "thumb_2"]


def curl(f1, f2, f3, fingers=FINGER_NAMES, z=0):
    return {f"{f}_{i + 1}": (a, 0, z if i == 0 else 0) for f in fingers for i, a in enumerate((f1, f2, f3))}


def mix(a, b, t):
    out = {}
    for name in set(a) | set(b):
        ra, rb = a.get(name, (0, 0, 0)), b.get(name, (0, 0, 0))
        out[name] = tuple(x + (y - x) * t for x, y in zip(ra, rb))
    return out


def offset(pose, extra):
    out = dict(pose)
    for name, r in extra.items():
        base = out.get(name, (0, 0, 0))
        out[name] = tuple(x + y for x, y in zip(base, r))
    return out


def shaken(pose, amount, rng, bones=FINGER_BONES):
    """The pose with every finger bone nudged at random: a tremble when keyed every couple of frames."""
    extra = {b: (rng.uniform(-amount, amount), 0, rng.uniform(-amount, amount) * 0.4) for b in bones}
    extra["hand"] = (rng.uniform(-amount, amount) * 0.5, rng.uniform(-amount, amount) * 0.5, 0)
    return offset(pose, extra)


OPEN = {}
RELAXED = {**curl(-8, -12, -8), "thumb_1": (-6, 0, 0), "thumb_2": (-8, 0, 0)}
IDLE_B = {**curl(-14, -20, -12), **curl(-4, -6, -4, ("index",)), "thumb_1": (-10, 0, 0), "thumb_2": (-14, 0, 0),
          "hand": (-4, 0, 0)}
FIST = {**curl(-82, -100, -62), "thumb_0": (-10, 0, -25), "thumb_1": (-35, 0, 0), "thumb_2": (-50, 0, 0)}
POINT = {**FIST, **curl(-4, -4, -2, ("index",))}
# Point with the fingertip pressed into the floor: the tip joint buckles back, the middle joint gives a little,
# the wrist bends back against the push and the curled fingers clench
POKE_PRESS = {**offset(FIST, curl(-6, -6, -4, ("middle", "ring", "pinky"))), "index_1": (-10, 0, 0),
              "index_2": (-20, 0, 0), "index_3": (26, 0, 0), "hand": (10, 0, 0), "thumb_1": (-42, 0, 0)}
TOUCH = {  # the reference picture: index reaching down, the rest loosely curled
    **curl(-6, -6, -4, ("index",)),
    **curl(-28, -42, -28, ("middle",)),
    **curl(-50, -58, -36, ("ring",)),
    **curl(-62, -62, -40, ("pinky",)),
    "thumb_0": (0, 0, -8), "thumb_1": (-8, 0, 0), "thumb_2": (-22, 0, 0),
    "hand": (-12, 0, 0),
}
CLAW = {**curl(-25, -55, -50), "thumb_1": (-20, 0, 0), "thumb_2": (-40, 0, 0), "hand": (18, 0, 0)}
FLAT = {**curl(5, 3, 0), "thumb_0": (0, 0, 8), "hand": (6, 0, 0)}  # sweeps and the crush
SPREAD = {  # nail volley: fingers fanned wide and bent back
    **curl(8, 2, 0, ("index",), 16), **curl(8, 2, 0, ("middle",), 5),
    **curl(8, 2, 0, ("ring",), -7), **curl(8, 2, 0, ("pinky",), -18),
    "thumb_0": (6, 0, 22), "thumb_1": (4, 0, 0), "hand": (12, 0, 0),
}
FLICK_HOOK = {  # index curled under the thumb, straining
    **curl(-40, -50, -30, ("middle", "ring", "pinky")),
    **curl(-62, -95, -70, ("index",)),
    "thumb_0": (-22, 0, -30), "thumb_1": (-12, 0, 0), "thumb_2": (-8, 0, 0),
}
FLICK_OUT = {**FLICK_HOOK, **curl(12, 6, 6, ("index",)), "thumb_0": (-26, 0, -34), "thumb_1": (-30, 0, 0)}
SNAP_READY = {
    **curl(-30, -40, -20, ("index",)), **curl(-28, -38, -22, ("middle",)),
    **curl(-62, -72, -40, ("ring",)), **curl(-72, -72, -40, ("pinky",)),
    "thumb_0": (-26, 0, -32), "thumb_1": (-22, 0, 0), "thumb_2": (-16, 0, 0),
}
SNAP_DONE = {**SNAP_READY, **curl(-85, -98, -58, ("middle",)), **curl(-18, -18, -8, ("index",)),
             "thumb_0": (-30, 0, -12), "thumb_1": (2, 0, 0), "thumb_2": (6, 0, 0)}
LIMP = {**curl(-22, -34, -22), "thumb_1": (-12, 0, 0), "thumb_2": (-18, 0, 0), "hand": (-38, 0, 0)}

POSES = {"Open": OPEN, "Fist": FIST, "Point": POINT, "PokePress": POKE_PRESS, "Touch": TOUCH, "Claw": CLAW, "Flat": FLAT, "Spread": SPREAD,
         "FlickHook": FLICK_HOOK, "FlickOut": FLICK_OUT, "SnapReady": SNAP_READY, "SnapDone": SNAP_DONE, "Limp": LIMP}

# Clips that loop in Godot (hand_boss.glb.import sets their loop mode)
LOOPING = ("Idle", "Hover", "FistTremble", "PokeStuck", "FlickHold", "Drumroll")


def set_pose(rig, pose):
    for pb in rig.pose.bones:
        pb.rotation_euler = [math.radians(a) for a in pose.get(pb.name, (0, 0, 0))]
    bpy.context.view_layer.update()


def make_action(rig, name, keys):
    """keys: (frame, pose) pairs, 30 frames a second, frame 1 at 0 s. Saved with a fake user so the glTF exporter
    picks it up."""
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for frame_no, pose in keys:
        set_pose(rig, pose)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_euler", frame=frame_no - 1)  # the exporter counts from frame 0
    rig.animation_data.action = None
    return act


def hold(pose):
    return [(1, pose), (2, pose)]


def tremble_loop(pose, frames, amount, rng, step=2):
    keys = [(f, shaken(pose, amount, rng)) for f in range(1, frames, step)]
    return keys + [(frames, keys[0][1])]


def hover_keys():
    """Claw pose with the fingers rippling, while it follows the player before an attack."""
    keys = []
    for f in range(1, 50, 4):
        phase = 2 * math.pi * (f - 1) / 48
        extra = {}
        for i, name in enumerate(FINGER_NAMES):
            a = 10 * math.sin(phase + i * 0.9)
            extra |= {f"{name}_1": (a, 0, 0), f"{name}_2": (a * 0.8, 0, 0), f"{name}_3": (a * 0.6, 0, 0)}
        extra["thumb_1"] = (6 * math.sin(phase + 4.0), 0, 0)
        keys.append((f, offset(CLAW, extra)))
    return keys


def drumroll_keys():
    """Fingers tap down one after another, pinky first, every 16 frames."""
    base = {**curl(-12, -10, -5), "thumb_1": (-8, 0, 0), "hand": (8, 0, 0)}
    keys = []
    for f in range(1, 18):
        extra = {}
        for i, name in enumerate(reversed(FINGER_NAMES)):
            centre = 3 + i * 3
            d = min(abs(f - centre), abs(f - centre - 16), abs(f - centre + 16))
            tap = max(0.0, 1 - d / 2.5)
            extra |= {f"{name}_1": (-38 * tap, 0, 0), f"{name}_2": (-12 * tap, 0, 0)}
        keys.append((f, offset(base, extra)))
    return keys


def build_actions(rig):
    rng = random.Random(SEED + 1)
    for name, pose in POSES.items():
        make_action(rig, name, hold(pose))

    make_action(rig, "Idle", [(1, RELAXED), (31, IDLE_B), (61, RELAXED)])
    make_action(rig, "Hover", hover_keys())
    make_action(rig, "Entrance", [(1, RELAXED), (25, offset(TOUCH, curl(-12, -6, -4, ("index",)))), (40, TOUCH)])

    # Fist slam: Clench, then FistTremble while it lines up and falls, then Release after the impact
    make_action(rig, "Clench", [(1, OPEN), (8, offset(FIST, curl(-6, -6, -4))), (11, FIST)])
    make_action(rig, "FistTremble", tremble_loop(FIST, 13, 4, rng))
    make_action(rig, "Release", [(1, FIST), (6, mix(FIST, RELAXED, 0.6)), (16, RELAXED)])

    # Poke: Point while it jabs. PokeStuck when the third jab is parried and the finger sticks in the floor
    others = [f"{n}_{i}" for n in ("middle", "ring", "pinky") for i in (1, 2, 3)]
    stuck = []
    for f in range(1, 24, 3):
        p = offset(POINT, {"hand": (-8 + rng.uniform(-6, 6), rng.uniform(-4, 4), 0)})
        stuck.append((f, shaken(p, 12, rng, others)))
    make_action(rig, "PokeStuck", stuck + [(25, stuck[0][1])])

    # Flick: FlickHold while it strains, then FlickRelease, which fires the orb 0.1 s in
    make_action(rig, "FlickHold", tremble_loop(FLICK_HOOK, 13, 3, rng))
    make_action(rig, "FlickRelease", [(1, FLICK_HOOK), (4, FLICK_OUT),
                                      (9, offset(FLICK_OUT, curl(-8, -4, -2, ("index",)))), (20, RELAXED)])

    # Snap: SnapReady, then Snap. The snap lands 0.1 s in; that is when the adds are called in
    make_action(rig, "Snap", [(1, SNAP_READY), (4, SNAP_DONE), (8, offset(SNAP_DONE, {"hand": (-8, 0, 0)})),
                              (22, RELAXED)])

    # Nail volley: Spread, then VolleyRecoil for each shot
    make_action(rig, "VolleyRecoil", [(1, SPREAD), (3, offset(SPREAD, {**curl(14, 6, 0), "hand": (12, 0, 0)})),
                                      (10, SPREAD)])

    make_action(rig, "Drumroll", drumroll_keys())

    make_action(rig, "Stagger", [
        (1, RELAXED),
        (4, offset(SPREAD, {"hand": (22, 0, 0)})),
        (9, shaken(mix(RELAXED, FIST, 0.4), 22, rng)),
        (14, shaken(mix(RELAXED, CLAW, 0.5), 18, rng)),
        (26, RELAXED),
    ])
    # Between phases: clench, shake, burst open
    roar = [(1, RELAXED), (10, FIST)]
    roar += [(f, shaken(FIST, 7, rng)) for f in range(12, 35, 2)]
    roar += [(39, offset(SPREAD, {**curl(10, 4, 0), "hand": (18, 0, 0)})), (48, SPREAD)]
    make_action(rig, "PhaseRoar", roar)
    make_action(rig, "Death", [
        (1, RELAXED),
        (5, offset(SPREAD, {"hand": (20, 0, 0)})),
        (11, shaken(FIST, 10, rng)),
        (17, offset(SPREAD, {"hand": (25, 0, 0)})),
        (24, shaken(CLAW, 14, rng)),
        (32, shaken(mix(CLAW, LIMP, 0.5), 8, rng)),
        (60, LIMP),
    ])
    set_pose(rig, {})


# ---------------------------------------------------------------------------------------------------------- export

def export_glb(rig, body):
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o in (rig, body))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_yup=True,
    )


# --------------------------------------------------------------------------------------------------------- preview

def emission_material(name, colour, strength):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nodes = mat.node_tree.nodes
    nodes.remove(nodes.get("Principled BSDF"))
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*colour, 1.0)
    em.inputs["Strength"].default_value = strength
    mat.node_tree.links.new(em.outputs["Emission"], nodes.get("Material Output").inputs["Surface"])
    return mat


def build_preview_scene():
    scene = bpy.context.scene
    coll = bpy.data.collections.new("Preview")
    scene.collection.children.link(coll)

    world = bpy.data.worlds.new("Synthwave")
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.0, 0.10, 1.0)
    scene.world = world

    bpy.ops.mesh.primitive_plane_add(size=800, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "PreviewGround"
    gm = bpy.data.materials.new("PreviewWater")
    try:
        gm.use_nodes = True
    except AttributeError:
        pass
    b = gm.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.03, 0.45, 0.55, 1.0)
    b.inputs["Roughness"].default_value = 0.06
    ground.data.materials.append(gm)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=24, location=(4, 220, 10))
    sun = bpy.context.active_object
    sun.name = "PreviewSun"
    sun.data.materials.append(emission_material("PreviewSunGlow", (1.0, 0.16, 0.01), 1.6))

    sun_light = bpy.data.lights.new("PreviewKey", "SUN")
    sun_light.energy = 3.0
    sun_light.color = (1.0, 0.75, 0.85)
    key = bpy.data.objects.new("PreviewKey", sun_light)
    key.rotation_euler = (math.radians(55), 0, math.radians(-30))
    fill_light = bpy.data.lights.new("PreviewFill", "SUN")
    fill_light.energy = 1.2
    fill_light.color = (0.3, 0.9, 1.0)
    fill = bpy.data.objects.new("PreviewFill", fill_light)
    fill.rotation_euler = (math.radians(120), 0, math.radians(160))
    cam = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    for o in (key, fill, cam):
        coll.objects.link(o)
    for o in (ground, sun):
        for c in o.users_collection:
            c.objects.unlink(o)
        coll.objects.link(o)
    scene.camera = cam

    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 32
    try:
        scene.eevee.use_raytracing = True
    except AttributeError:
        pass
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 750
    return cam, ground


def render(cam, path, location, target, lens=35):
    cam.location = location
    cam.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def hang(rig, pose, tip_bone, tip_height):
    """Turns the hand to hang fingers-down with its back to the camera, the tip of tip_bone at tip_height."""
    rig.location = (0, 0, 0)
    rig.rotation_euler = (math.radians(-90), 0, math.radians(180))
    set_pose(rig, pose)
    tip = rig.matrix_world @ rig.pose.bones[tip_bone].tail
    rig.location = (-tip.x, -tip.y, tip_height - tip.z)
    bpy.context.view_layer.update()


def montage(paths, columns, out_path):
    """Tiles same-sized renders into one image, left to right, top to bottom."""
    import numpy as np
    tiles = []
    for path in paths:
        img = bpy.data.images.load(path)
        w, h = img.size
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(img)
    h, w = tiles[0].shape[:2]
    rows = (len(tiles) + columns - 1) // columns
    sheet = np.zeros((rows * h, columns * w, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, tile in enumerate(tiles):
        r = rows - 1 - i // columns  # image rows run bottom to top
        c = i % columns
        sheet[r * h:(r + 1) * h, c * w:(c + 1) * w] = tile
    out = bpy.data.images.new("sheet", columns * w, rows * h, alpha=True)
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    print("rendered", out_path)


def previews(rig, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cam, ground = build_preview_scene()
    scene = bpy.context.scene

    hang(rig, TOUCH, "index_3", 0.15)
    render(cam, os.path.join(out_dir, "hand_touch.png"), v(7, -15, 2.2), v(0, 0, 4.5))

    # Pose sheet: every pose from above the back of the hand and from the thumb side, two poses to a row
    ground.hide_render = True
    scene.render.resolution_x, scene.render.resolution_y = 480, 320
    rig.rotation_euler = (0, 0, 0)
    rig.location = (0, 0, 6)
    target = v(-0.3, 2.8, 6)
    tiles = []
    for name, pose in POSES.items():
        set_pose(rig, pose)
        for view, location in (("back", v(-4.5, -1.5, 12.5)), ("side", v(-8.5, 3.2, 4.8))):
            path = os.path.join(out_dir, "tiles", f"{name}_{view}.png")
            render(cam, path, location, target, 38)
            tiles.append(path)
    montage(tiles, 4, os.path.join(out_dir, "hand_pose_sheet.png"))
    print("pose sheet order:", ", ".join(POSES))
    scene.render.resolution_x, scene.render.resolution_y = 1200, 750
    ground.hide_render = False

    rig.location = (0, 0, 0)
    rig.rotation_euler = (0, 0, 0)
    set_pose(rig, {})


# ------------------------------------------------------------------------------------------------------------ main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview_dir = os.path.join(ROOT, "art", "blender", "previews")
    if "--preview-dir" in argv:
        preview_dir = argv[argv.index("--preview-dir") + 1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30  # the clips are keyed in 30ths of a second
    rng = random.Random(SEED)

    body = build_mesh(rng)
    body.data.materials.append(build_material())
    rig = build_rig()
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    build_actions(rig)
    print(f"hand: {tri_count(body)} triangles, {len(rig.data.bones)} bones")

    export_glb(rig, body)
    print("exported", GLB_PATH)
    if "--no-preview" not in argv:
        previews(rig, preview_dir)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("saved", BLEND_PATH)


main()
