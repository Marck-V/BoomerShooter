"""Builds the player's offhand shield: a classic round buckler with a ribbed back.

Run from the project root (Blender 5.1 or newer):
    blender --background --factory-startup --python tools/assetgen/player_shield.py -- [--preview-dir DIR] [--no-preview]

Writes:
    art/blender/player_shield.blend   the source file (rebuilt from scratch every run, so hand edits there are lost)
    models/player_shield/player_shield.glb
                                      what Godot uses (scripts/player/shield_model.gd): every part joined into one
                                      mesh, front facing up (+Y in Godot), with the materials Body, BodyLight, Rim, Gem
    DIR/player_shield_*.png           preview renders (default art/blender/previews)

The front faces enemies: stepped rings slope up to a low faceted dome with the gem on top, studs round the edge.
The back faces the player: six tapering ribs brace the plate from a hub, with a glowing ring between them and a small
gem in the hub. The edge is smooth because the thrown shield ricochets between enemies rather than cutting them.

Parts, matching the three the shield script recolours for its states (scripts/player/offhand_shield.gd):
    Front_Body, Front_Studs, Back_Body       body (dark metal)
    Front_Rim, Back_BackRim                  rim (yellow, cyan while parrying, green while grappling)
    Front_Gem, Back_BackGem                  gem
The back carries its own rim light and gem so the player keeps that state feedback while the front faces away.
It is 0.52 m across like the current shield. The front faces -Y in Blender, the back +Y.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "player_shield.blend")
GLB_PATH = os.path.join(ROOT, "models", "player_shield", "player_shield.glb")

RIM = (1.0, 0.72, 0.1)      # the shield script's RIM_BASE, brought into 0-1
GEM = (0.15, 0.78, 1.0)     # GEM_BASE
BODY = (0.2, 0.25, 0.42)    # the current body's main plate
BODY_LIGHT = (0.3, 0.36, 0.55)
RADIUS = 0.26


def v(*a):
    return Vector(a)


# ------------------------------------------------------------------------------------------------------ materials

def _nodes(mat):
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    return mat.node_tree.nodes


def glow_material(name, colour, strength):
    mat = bpy.data.materials.new(name)
    b = _nodes(mat).get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Emission Color"].default_value = (*colour, 1.0)
    b.inputs["Emission Strength"].default_value = strength
    return mat


def body_material(name, colour, metallic=0.6, roughness=0.35):
    mat = bpy.data.materials.new(name)
    b = _nodes(mat).get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return mat


# ---------------------------------------------------------------------------------------------------------- helpers

def new_collection(name):
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    return coll


def mesh_object(name, bm, collection, materials, location):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = location
    collection.objects.link(ob)
    return ob


def face_camera(bm):
    """Shapes are drawn in the XY plane facing +Z; stand them up to face -Y (towards the camera)."""
    bmesh.ops.rotate(bm, verts=bm.verts, cent=v(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))


def finish(bm, name, coll, mats, x):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    face_camera(bm)
    return mesh_object(name, bm, coll, mats, (x, 0, 0))


def circle(radius, segments=24, start=0.0):
    return [(math.cos(start + math.tau * i / segments) * radius, math.sin(start + math.tau * i / segments) * radius)
            for i in range(segments)]


def inset_outline(points, width):
    """Moves every corner of a convex outline (counter-clockwise) inwards so each edge sits `width` further in."""
    n = len(points)
    pts = [Vector(p) for p in points]
    out = []
    for i in range(n):
        prev, cur, nxt = pts[i - 1], pts[i], pts[(i + 1) % n]
        e1 = (cur - prev).normalized()
        e2 = (nxt - cur).normalized()
        n1 = Vector((-e1.y, e1.x))  # inward normal of a counter-clockwise edge
        n2 = Vector((-e2.y, e2.x))
        bisector = (n1 + n2).normalized()
        out.append(cur + bisector * (width / max(bisector.dot(n1), 0.2)))
    return [(p.x, p.y) for p in out]


def prism(bm, points, z0, z1):
    """Adds a closed prism with a convex outline (XY, counter-clockwise) between z0 and z1 to bm. Returns its verts."""
    bottom = [bm.verts.new((x, y, z0)) for x, y in points]
    top = [bm.verts.new((x, y, z1)) for x, y in points]
    bm.faces.new(top)
    bm.faces.new(bottom[::-1])
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bottom[i], bottom[j], top[j], top[i]])
    return bottom + top


def frustum(bm, r0, r1, z0, z1, segments=16, start=0.0):
    """A cone section from radius r0 at z0 up to r1 at z1, capped both ends."""
    low = [bm.verts.new((x, y, z0)) for x, y in circle(r0, segments, start)]
    high = [bm.verts.new((x, y, z1)) for x, y in circle(r1, segments, start)]
    bm.faces.new(high)
    bm.faces.new(low[::-1])
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new([low[i], low[j], high[j], high[i]])


def band(bm, points, width, z0, z1):
    """A flat band just inside a convex outline, `width` wide, from z0 to z1."""
    inner = inset_outline(points, width)
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        prism(bm, [points[i], points[j], inner[j], inner[i]], z0, z1)


def gem(bm, radius, height, z, sides=8):
    """A cut gem sitting at z: a flat table on top, a short pavilion below."""
    girdle = [bm.verts.new((x, y, z + height * 0.35)) for x, y in circle(radius, sides)]
    table = [bm.verts.new((x, y, z + height)) for x, y in circle(radius * 0.55, sides, math.pi / sides)]
    culet = bm.verts.new((0, 0, z))
    bm.faces.new(table)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new([girdle[i], girdle[j], table[j]])
        bm.faces.new([table[j], table[i], girdle[i]])
        bm.faces.new([girdle[j], girdle[i], culet])


def back_gem(bm, radius, height, z, cx=0.0, cy=0.0, sides=8):
    """A cut gem on the back, pointing away from the shield (towards -Z) from z."""
    start = len(bm.verts)
    gem(bm, radius, height, 0.0, sides)
    bm.verts.ensure_lookup_table()
    for vert in bm.verts[start:]:
        vert.co = Vector((vert.co.x + cx, vert.co.y + cy, z - vert.co.z))


# ----------------------------------------------------------------------------------------------------------- boss

def build_boss(x, m, coll, prefix):
    """The front: what enemies see. The back is built by one of the back_* functions."""
    body = bmesh.new()
    prism(body, circle(RADIUS), -0.03, 0.0)                     # the disc
    frustum(body, 0.215, 0.2, 0.0, 0.012)                         # first step
    frustum(body, 0.17, 0.11, 0.012, 0.04)                        # sloped ring up to the boss
    dome = bmesh.ops.create_uvsphere(body, u_segments=8, v_segments=6, radius=0.1)
    for vert in dome["verts"]:                                    # flatten it into a low faceted dome
        vert.co.z = max(vert.co.z, 0.0) * 0.55 + 0.035
    bmesh.ops.remove_doubles(body, verts=dome["verts"], dist=1e-4)
    finish(body, prefix + "Body", coll, [m["body"]], x)

    studs = bmesh.new()
    for i in range(8):                                            # studs round the edge, between rim and first step
        a = math.tau * (i + 0.5) / 8
        pts = [(math.cos(a) * 0.233 + px, math.sin(a) * 0.233 + py) for px, py in circle(0.012, 6)]
        prism(studs, pts, 0.0, 0.014)
    finish(studs, prefix + "Studs", coll, [m["body_light"]], x)

    rim = bmesh.new()
    band(rim, circle(RADIUS + 0.004, 32), 0.018, -0.032, 0.012)  # neon edge
    band(rim, circle(0.118, 16), 0.008, 0.04, 0.046)             # thin ring where the slope meets the dome
    finish(rim, prefix + "Rim", coll, [m["rim"]], x)

    stone = bmesh.new()
    gem(stone, 0.042, 0.04, 0.083)
    finish(stone, prefix + "Gem", coll, [m["gem"]], x)


# ---------------------------------------------------------------------------------------------------------- backs
# The back is what the player sees while holding it, so each one carries its own rim light and a small gem: the shield
# script recolours those for parry, block, recovery and grapple, and that feedback has to stay on the player's side.
BACK_Z = -0.03


def back_rim_light():
    rim = bmesh.new()
    band(rim, circle(RADIUS + 0.004, 32), 0.014, BACK_Z - 0.01, BACK_Z)   # the edge glows on the back too
    return rim


def back_ribs(x, m, coll, prefix):
    """The Ribbed Frame: six tapering ribs brace the plate from a hub, with a glowing ring between them."""
    body = bmesh.new()
    for i in range(6):
        a = math.tau * i / 6 + math.pi / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0)) * 0.007
        inner, outer = d * 0.07, d * 0.24
        quad = [inner + Vector((0, 0, BACK_Z)), outer + Vector((0, 0, BACK_Z)),
                outer + Vector((0, 0, BACK_Z - 0.008)), inner + Vector((0, 0, BACK_Z - 0.04))]
        vs = [body.verts.new(q + side * sgn) for sgn in (-1, 1) for q in quad]
        a_, b_ = vs[:4], vs[4:]
        body.faces.new(a_[::-1])
        body.faces.new(b_)
        for k in range(4):
            j = (k + 1) % 4
            body.faces.new([a_[k], a_[j], b_[j], b_[k]])
    frustum(body, 0.06, 0.078, BACK_Z - 0.045, BACK_Z)                   # hub
    finish(body, prefix + "Body", coll, [m["body_light"]], x)

    rim = back_rim_light()
    band(rim, circle(0.205, 36), 0.008, BACK_Z - 0.004, BACK_Z)          # glowing ring between the ribs
    finish(rim, prefix + "BackRim", coll, [m["rim"]], x)
    stone = bmesh.new()
    back_gem(stone, 0.03, 0.022, BACK_Z - 0.045)                         # set in the hub
    finish(stone, prefix + "BackGem", coll, [m["gem"]], x)


# --------------------------------------------------------------------------------------------------------- preview

def build_preview_scene():
    scene = bpy.context.scene
    coll = new_collection("Preview")
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
    cam = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    coll.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 32
    scene.view_settings.view_transform = "Standard"
    return cam


def render(cam, path, location, target, lens=50, size=(1500, 650)):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    cam.location = location
    cam.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def held_view(cam, path, x):
    """Roughly the first-person view: the shield sits low on the left, turned in towards the middle of the screen."""
    objs = [o for o in bpy.data.objects if o.type == "MESH" and abs(o.location.x - x) < 0.01]
    saved = [(o, o.location.copy(), o.rotation_euler.copy()) for o in objs]
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in objs
    # The game holds it at HELD_POS (-0.7, -0.42, -0.62 in the camera's space): left, down, forward.
    # Here the camera looks along +Y, so the shield goes left, forward and down. It is held the real way round: the
    # front (-Y) faces away and the back faces the player, turned in towards the middle of the screen.
    for o in objs:
        o.location = (o.location.x - x - 0.42, 0.72, -0.3)
        o.rotation_euler = (math.radians(12), math.radians(-6), math.radians(220))
    render(cam, path, v(0, 0, 0), v(0, 1, 0), 20, (1050, 600))
    for o, loc, rot in saved:
        o.location, o.rotation_euler = loc, rot
    for o in bpy.data.objects:
        o.hide_render = False


def previews(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cam = build_preview_scene()
    for light in (o for o in bpy.data.objects if o.type == "LIGHT"):  # light the back the way the front was lit
        light.rotation_euler.z += math.pi
    render(cam, os.path.join(out_dir, "player_shield_back.png"), v(0, 1.6, 0.0), v(0, 0, 0), 50, (900, 900))
    render(cam, os.path.join(out_dir, "player_shield_back_angle.png"), v(-0.9, 1.2, 0.6), v(0, 0, 0), 50, (900, 900))
    held_view(cam, os.path.join(out_dir, "player_shield_held.png"), 0.0)
    for light in (o for o in bpy.data.objects if o.type == "LIGHT"):  # and the front as it was
        light.rotation_euler.z -= math.pi
    render(cam, os.path.join(out_dir, "player_shield_front.png"), v(0.9, -1.2, 0.6), v(0, 0, 0), 50, (900, 900))


# ---------------------------------------------------------------------------------------------------------- export

def export_glb(coll):
    """Joins the shield into one mesh, turns the front from -Y to +Z (+Y in Godot, where the old model faced) and
    exports it. Run after the .blend is saved: it changes the scene."""
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    parts = [o for o in coll.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    shield = bpy.context.view_layer.objects.active
    shield.name = "PlayerShield"
    shield.rotation_euler = (math.radians(-90), 0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False)
    print("exported", GLB_PATH)


# ------------------------------------------------------------------------------------------------------------ main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview_dir = os.path.join(ROOT, "art", "blender", "previews")
    if "--preview-dir" in argv:
        preview_dir = argv[argv.index("--preview-dir") + 1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = {
        "body": body_material("Body", BODY),
        "body_light": body_material("BodyLight", BODY_LIGHT, 0.7, 0.3),
        "rim": glow_material("Rim", RIM, 1.6),
        "gem": glow_material("Gem", GEM, 1.6),
    }
    coll = new_collection("Shield")
    build_boss(0.0, m, coll, "Front_")
    back_ribs(0.0, m, coll, "Back_")

    if "--no-preview" not in argv:
        previews(preview_dir)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("saved", BLEND_PATH)
    export_glb(coll)


main()
