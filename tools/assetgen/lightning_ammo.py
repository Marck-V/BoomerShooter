"""Builds the lightning gun's ammo pickup: one of the glass vials from the side of the gun, stood upright, with an arc
rattling inside it.

Run from the project root (Blender 4.3 or newer):
    blender --background --factory-startup --python tools/assetgen/lightning_ammo.py

Writes:
    art/blender/lightning_ammo.blend         the source (rebuilt from scratch every run)
    models/weapons/lightning_ammo.glb        what the pickup uses (scripts/pickups/pickup.gd, ammo_paths)

The vial copies the gun's: a glass tube between two copper caps with a nub on each end (see the "glass tubes" in
lightning_gun.py). It is modelled standing on +Z (Godot's up), centred on the origin and about 0.27 m tall; the pickup
scales ammo models up by 2. Three surfaces (copper, glass, glowing arc), so it costs three draw calls.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "lightning_ammo.blend")
GLB_PATH = os.path.join(ROOT, "models", "weapons", "lightning_ammo.glb")

COPPER = (0.88, 0.52, 0.28)
ELECTRIC = (0.15, 0.45, 1.0)

RADIUS = 0.045            # the glass
LENGTH = 0.17             # the glass, between the caps
CAP_RADIUS = RADIUS + 0.008
CAP_LENGTH = 0.03
SIDES = 14


def v(*a):
    return Vector(a)


def surface(name, colour, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    b = mat.node_tree.nodes.get("Principled BSDF")
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


def tube(bm, p0, p1, r0, r1=None, segments=SIDES):
    """A capped cylinder (or cone) from p0 to p1."""
    r1 = r0 if r1 is None else r1
    p0, p1 = v(*p0), v(*p1)
    axis = p1 - p0
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r0, radius2=r1, depth=axis.length)
    rot = axis.normalized().to_track_quat("Z", "Y").to_matrix()
    bmesh.ops.rotate(bm, verts=ret["verts"], cent=v(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=ret["verts"], vec=(p0 + p1) / 2)


def ball(bm, centre, radius, segs=6):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs // 2), radius=radius)
    bmesh.ops.translate(bm, verts=ret["verts"], vec=v(*centre))


def bolt(bm, p0, p1, rng, kinks, jitter, radius):
    """A jagged arc from p0 to p1, made of thin tubes."""
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


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {"copper": surface("Copper", COPPER, 0.5, 0.4),
            "glass": glass("Glass", (0.5, 0.75, 1.0), 0.2),
            "arc": glow("Arc", (0.2, 0.5, 1.0), 1.6)}
    parts = {key: bmesh.new() for key in mats}
    rng = random.Random(11)
    half = LENGTH / 2

    tube(parts["glass"], (0, 0, -half), (0, 0, half), RADIUS)
    for sign in (-1, 1):
        tube(parts["copper"], (0, 0, sign * half), (0, 0, sign * (half + CAP_LENGTH)), CAP_RADIUS)        # cap
        tube(parts["copper"], (0, 0, sign * (half + CAP_LENGTH)), (0, 0, sign * (half + CAP_LENGTH + 0.008)),
             CAP_RADIUS * 0.7)                                                                           # step
        ball(parts["copper"], (0, 0, sign * (half + CAP_LENGTH + 0.016)), 0.014)                          # terminal nub
    # the arcs inside: one long one end to end, and two short ones off it
    inner = half - 0.004
    bolt(parts["arc"], (0, 0, -inner), (0, 0, inner), rng, 7, 0.22, 0.0045)
    for _ in range(2):
        z = rng.uniform(-0.05, 0.05)
        d = v(rng.uniform(-1, 1), rng.uniform(-1, 1), 0).normalized()
        bolt(parts["arc"], (0, 0, z), v(0, 0, z) + d * (RADIUS - 0.006), rng, 3, 0.3, 0.003)

    me = bpy.data.meshes.new("LightningAmmo")
    merged = bmesh.new()
    for index, (key, bm) in enumerate(parts.items()):
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
    ob = bpy.data.objects.new("LightningAmmo", me)
    bpy.context.scene.collection.objects.link(ob)

    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False)
    print("exported", GLB_PATH)


main()
