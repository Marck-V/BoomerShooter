"""Builds the enemy shield: a faceted crystal cage around the enemy's whole body.

Run from the project root (Blender 5.1 or newer):
    blender --background --factory-startup --python tools/assetgen/enemy_shield.py -- [--preview-dir DIR] [--no-preview]

Writes:
    art/blender/enemy_shield.blend         the source file (rebuilt from scratch every run, so hand edits there are lost)
    models/enemy_shield/enemy_shield.glb   what Godot uses (scenes/enemies/shield.tscn), with the Cage and Gem meshes
    DIR/enemy_shield_*.png                 preview renders (default art/blender/previews)

In Godot the cage is drawn by shaders/enemies/enemy_shield.gdshader (it replaces the glTF materials), which needs the
per-tile data described in build_cage(). The import keeps LODs and vertex compression off so that data survives.

The cage sits around a grey stand-in capsule the size of the shield hitbox in scenes/enemies/shield.tscn
(radius 0.4, height 1.8, centred 1 m up), with its origin at the enemy's feet. Blender -Y is the enemy's front.
Parts:
    Cage   80 loose tiles of a geodesic shell, each a translucent pane in a glowing rim
    Gem    a crystal floating above the head
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLEND_PATH = os.path.join(ROOT, "art", "blender", "enemy_shield.blend")
GLB_PATH = os.path.join(ROOT, "models", "enemy_shield", "enemy_shield.glb")
SEED = 11

CYAN = (0.05, 0.85, 1.0)
MAGENTA = (1.0, 0.1, 0.65)

CENTRE = (0.0, 0.0, 1.0)   # middle of the hitbox capsule
SHELL_SCALE = (0.78, 0.78, 1.18)  # half-widths of the egg-shaped shell
SHELL_DETAIL = 2           # icosphere subdivisions: 2 gives 80 panes
RIM_WIDTH = 0.022          # each tile's rim; two neighbouring rims make one frame bar
RIM_DEPTH = 0.025          # how far the rim stands out from the pane
GEM_HEIGHT = 2.45


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


def pane_material(name, colour, alpha):
    mat = bpy.data.materials.new(name)
    b = _nodes(mat).get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Roughness"].default_value = 0.1
    b.inputs["Alpha"].default_value = alpha
    b.inputs["Emission Color"].default_value = (*colour, 1.0)
    b.inputs["Emission Strength"].default_value = 0.6
    try:
        mat.surface_render_method = "BLENDED"
    except AttributeError:
        mat.blend_method = "BLEND"
    mat.use_backface_culling = False
    return mat


def flat_material(name, colour, roughness=0.6):
    mat = bpy.data.materials.new(name)
    b = _nodes(mat).get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Roughness"].default_value = roughness
    return mat


# ---------------------------------------------------------------------------------------------------------- helpers

def mesh_object(name, bm, collection, materials):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    return ob


def new_collection(name):
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    return coll


def stand_in(coll, mat):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.4)
    for vert in bm.verts:  # stretch the sphere into a capsule 1.8 tall
        vert.co.z += 0.5 if vert.co.z > 0 else -0.5
    bmesh.ops.translate(bm, verts=bm.verts, vec=v(*CENTRE))
    return mesh_object("StandIn", bm, coll, [mat])


# ---------------------------------------------------------------------------------------------------------- cage

def shell():
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=SHELL_DETAIL, radius=1.0)
    bmesh.ops.scale(bm, vec=v(*SHELL_SCALE), verts=bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=v(*CENTRE))
    return bm


def to_godot(p):
    """Blender (x, y, z) is Godot (x, z, -y) after the glTF export."""
    return p.x, p.z, -p.y


def build_cage(mats):
    """One mesh of 80 loose tiles. Each tile is a translucent pane (material 0) in a glowing rim with a small lip
    (material 1). Every vertex of a tile carries the tile's data for the Godot shader, which flashes whole panes
    and flings them apart on break:
        UV  = tile centre x, y      (Godot space, metres)
        UV2 = tile centre z, seed   (seed is 0-1 for a pane vertex, 2-3 for a rim vertex)
    The V of each UV is stored flipped because the glTF export flips it back."""
    coll = new_collection("EnemyShield")
    rng = random.Random(SEED)
    source = shell()
    bm = bmesh.new()
    uv_centre = bm.loops.layers.uv.new("TileCentre")
    uv_data = bm.loops.layers.uv.new("TileData")

    for face in source.faces:
        centre = face.calc_center_median()
        seed = rng.random()
        verts = [bm.verts.new(vert.co) for vert in face.verts]
        tile = bm.faces.new(verts)
        tile.normal_update()
        normal = tile.normal.copy()
        if normal.dot(centre - v(*CENTRE)) < 0:
            tile.normal_flip()
            normal = -normal
        pane = bmesh.ops.inset_individual(bm, faces=[tile], thickness=RIM_WIDTH)["faces"]  # the rim faces
        for rim in pane:
            rim.material_index = 1
        lip = bmesh.ops.extrude_face_region(bm, geom=pane)
        lip_verts = [e for e in lip["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, verts=lip_verts, vec=normal * RIM_DEPTH)
        tile_faces = {tile} | {f for vert in lip_verts for f in vert.link_faces} | set(pane)
        gx, gy, gz = to_godot(centre)
        for f in tile_faces:
            if not f.is_valid:
                continue
            rim_flag = 2.0 if f.material_index == 1 else 0.0
            for loop in f.loops:
                loop[uv_centre].uv = (gx, 1.0 - gy)
                loop[uv_data].uv = (gz, 1.0 - (seed + rim_flag))
    source.free()
    cage = mesh_object("Cage", bm, coll, [mats["cyan_pane"], mats["cyan_glow"]])

    gem = bmesh.new()
    bmesh.ops.create_icosphere(gem, subdivisions=1, radius=0.13)
    bmesh.ops.scale(gem, vec=v(0.8, 0.8, 1.6), verts=gem.verts)  # a stretched, faceted crystal
    gem_obj = mesh_object("Gem", gem, coll, [mats["magenta_glow"]])
    gem_obj.location = (0, 0, GEM_HEIGHT)  # its own origin, so Godot can spin it in place
    return cage, gem_obj


def export_glb(objects):
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(o in objects)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False)


# --------------------------------------------------------------------------------------------------------- preview

def build_preview_scene(mats):
    scene = bpy.context.scene
    coll = new_collection("Preview")
    stand_in(coll, mats["standin"])

    world = bpy.data.worlds.new("Synthwave")
    _nodes(world)
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.10, 0.0, 0.05, 1.0)
    scene.world = world

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    mesh_object("PreviewGround", bm, coll, [flat_material("PreviewFloor", (0.04, 0.03, 0.06), 0.3)])

    for name, energy, colour, rot in (("PreviewKey", 3.0, (1.0, 0.8, 0.9), (55, 0, -30)),
                                      ("PreviewFill", 1.0, (0.3, 0.9, 1.0), (120, 0, 160))):
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


def render(cam, path, location, target, lens=45, size=(900, 900)):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    cam.location = location
    cam.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def previews(mats, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cam = build_preview_scene(mats)
    target = v(0, 0, 1.2)
    render(cam, os.path.join(out_dir, "enemy_shield_front.png"), v(0, -5.5, 1.6), target)
    render(cam, os.path.join(out_dir, "enemy_shield_three_quarter.png"), v(3.0, -4.2, 2.6), target)
    # roughly what the player sees from a few metres away, eye height 1.7
    render(cam, os.path.join(out_dir, "enemy_shield_player_view.png"), v(-1.5, -7.5, 1.7), target, 35,
           (1200, 750))


# ------------------------------------------------------------------------------------------------------------ main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview_dir = os.path.join(ROOT, "art", "blender", "previews")
    if "--preview-dir" in argv:
        preview_dir = argv[argv.index("--preview-dir") + 1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {
        "standin": flat_material("StandIn", (0.35, 0.35, 0.38)),
        "cyan_glow": glow_material("CyanGlow", CYAN, 4.0),
        "magenta_glow": glow_material("MagentaGlow", MAGENTA, 4.0),
        "cyan_pane": pane_material("CyanPane", CYAN, 0.22),
    }
    cage, gem = build_cage(mats)
    export_glb([cage, gem])
    print("exported", GLB_PATH)

    if "--no-preview" not in argv:
        previews(mats, preview_dir)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("saved", BLEND_PATH)


main()
