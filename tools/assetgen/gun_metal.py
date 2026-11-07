"""Gunmetal texturing for the Blender asset scripts (run inside Blender 4.3+, which brings numpy).

    import gun_metal
    material = gun_metal.texture_metal(objects, [metal, metal_light, copper], "art/blender/textures", "lightning_gun")

Takes the meshes of a gun and a list of three materials (dark steel, light steel, copper, in that order), unwraps every face that uses one of the given flat-colour materials into ONE shared atlas,
bakes ambient occlusion and an edge mask from the geometry, and paints two small textures from them:
    <name>_albedo.png   blued gunmetal, worn silver along the edges, scratches, grime in the crevices
    <name>_orm.png      glTF-style packed map: red = occlusion, green = roughness, blue = metallic
Then merges all those materials into a single "GunMetal" material, so the gun needs fewer draw calls than before
(one surface for all its metal) and only two texture reads, with no normal map. Faces with other materials (glow,
glass) are left alone. Returns the material.

Cheap by design: 256 px maps, nearest filtering (the PSX look, and no mip blur), one material, baked wear instead of
shader work. The edge and occlusion detail is baked from the real geometry, so any gun built from boxes and
cylinders gets sensible wear without hand painting.
"""
import math
import os

import bmesh
import bpy
import numpy as np

# sRGB colours, as painted (the PNG stores them as they are)
STEEL_DARK = (0.25, 0.28, 0.33)       # blued gunmetal
STEEL_LIGHT = (0.48, 0.51, 0.56)
COPPER = (0.80, 0.47, 0.26)
WORN_STEEL = (0.82, 0.84, 0.88)        # bare metal showing through where the bluing has worn off
WORN_COPPER = (0.93, 0.62, 0.40)
ROUGH = (0.34, 0.27, 0.32)             # base roughness: dark steel, light steel, copper

OFF_ATLAS = 5.0                        # UVs of faces that must not bake: far outside the image


# ------------------------------------------------------------------------------------------------------- unwrap

def _unwrap(objects, metal_mats, margin):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    for ob in objects:
        bm = bmesh.from_edit_mesh(ob.data)
        mats = list(ob.data.materials)
        for face in bm.faces:
            if mats[face.material_index] in metal_mats:
                face.select_set(True)
        bmesh.update_edit_mesh(ob.data)
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=margin, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # every other face (glow, glass) is kept out of the atlas so baking leaves it alone
    for ob in objects:
        mats = list(ob.data.materials)
        layer = ob.data.uv_layers.active
        for poly in ob.data.polygons:
            if mats[poly.material_index] not in metal_mats:
                for index in poly.loop_indices:
                    layer.data[index].uv = (OFF_ATLAS, OFF_ATLAS)


# ---------------------------------------------------------------------------------------------------------- bake

def _bake_material(name, image, emission):
    """A material that bakes into `image`: emission(nodes, links) returns the socket to bake (None: AO only)."""
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    nodes.active = tex
    tex.select = True
    shader = nodes.new("ShaderNodeEmission")
    socket = emission(nodes, links)
    if socket is not None:
        links.new(socket, shader.inputs["Color"])
    links.new(shader.outputs["Emission"], out.inputs["Surface"])
    return mat


def _edge_socket(radius):
    def build(nodes, links):
        bevel = nodes.new("ShaderNodeBevel")
        bevel.inputs["Radius"].default_value = radius
        bevel.samples = 8
        geometry = nodes.new("ShaderNodeNewGeometry")
        dot = nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        links.new(bevel.outputs["Normal"], dot.inputs[0])
        links.new(geometry.outputs["Normal"], dot.inputs[1])
        flip = nodes.new("ShaderNodeMath")                  # 1 - dot: 0 on flat faces, biggest at sharp corners
        flip.operation = "SUBTRACT"
        flip.inputs[0].default_value = 1.0
        links.new(dot.outputs["Value"], flip.inputs[1])
        gain = nodes.new("ShaderNodeMath")
        gain.operation = "MULTIPLY"
        gain.use_clamp = True
        gain.inputs[1].default_value = 3.5                  # a 90 degree edge reaches 1, a 45 degree facet edge ~0.3
        links.new(flip.outputs["Value"], gain.inputs[0])
        rgb = nodes.new("ShaderNodeCombineColor")
        for channel in ("Red", "Green", "Blue"):
            links.new(gain.outputs["Value"], rgb.inputs[channel])
        return rgb.outputs["Color"]
    return build


def _id_socket(colour):
    def build(nodes, links):
        rgb = nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*colour, 1.0)
        return rgb.outputs[0]
    return build


def _bake(objects, metal_mats, kind, size, radius=0.005):
    scene = bpy.context.scene
    image = bpy.data.images.new(f"bake_{kind}", size, size, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "Non-Color"
    ids = {mat: _id_socket(colour) for mat, colour in zip(metal_mats, ((1, 0, 0), (0, 1, 0), (0, 0, 1)))}
    made = {}

    def temp_for(original):
        if original not in made:
            if kind == "ids":
                socket = ids.get(original, _id_socket((0, 0, 0)))
            elif kind == "edge":
                socket = _edge_socket(radius)
            else:
                socket = _id_socket((0, 0, 0))
            made[original] = _bake_material(f"bake_{kind}_{original.name}", image, socket)
        return made[original]

    saved = []
    for ob in objects:
        saved.append([slot.material for slot in ob.material_slots])
        for slot in ob.material_slots:
            slot.material = temp_for(slot.material)

    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    scene.render.bake.use_clear = True
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="AO" if kind == "ao" else "EMIT")

    for ob, originals in zip(objects, saved):
        for slot, material in zip(ob.material_slots, originals):
            slot.material = material
    for material in made.values():
        bpy.data.materials.remove(material)

    pixels = np.empty(size * size * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(size, size, 4)[:, :, :3]


# --------------------------------------------------------------------------------------------------------- paint

def _noise(size, cells, rng):
    """Smooth value noise in 0..1, `cells` random blobs across."""
    grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
    t = np.linspace(0.0, cells, size, endpoint=False, dtype=np.float32)
    i = t.astype(np.int32)
    f = t - i
    f = f * f * (3.0 - 2.0 * f)
    top = grid[i][:, i] * (1 - f)[None, :] + grid[i][:, i + 1] * f[None, :]
    bottom = grid[i + 1][:, i] * (1 - f)[None, :] + grid[i + 1][:, i + 1] * f[None, :]
    return top * (1 - f)[:, None] + bottom * f[:, None]


def _fbm(size, rng, octaves=(4, 8, 16, 32)):
    total = np.zeros((size, size), dtype=np.float32)
    weight = 1.0
    for cells in octaves:
        total += _noise(size, cells, rng) * weight
        weight *= 0.5
    return total / sum(0.5 ** k for k in range(len(octaves)))


def _scratches(size, rng, count):
    mask = np.zeros((size, size), dtype=np.float32)
    for _ in range(count):
        x, y = rng.random(2) * size
        angle = rng.random() * math.tau
        length = rng.uniform(6, 40)
        steps = int(length)
        xs = (x + np.cos(angle) * np.arange(steps)).astype(int) % size
        ys = (y + np.sin(angle) * np.arange(steps)).astype(int) % size
        mask[ys, xs] = rng.uniform(0.4, 1.0)
    return mask


def _smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _paint(ids, edge, ao, size, seed):
    rng = np.random.default_rng(seed)
    which = np.argmax(ids, axis=2)                          # 0 dark steel, 1 light steel, 2 copper
    which = np.where(ids.sum(axis=2) < 0.3, 0, which)       # nothing baked here (gaps between islands): dark steel
    base = np.array([STEEL_DARK, STEEL_LIGHT, COPPER], dtype=np.float32)[which]
    worn = np.array([WORN_STEEL, WORN_STEEL, WORN_COPPER], dtype=np.float32)[which]
    rough = np.array(ROUGH, dtype=np.float32)[which]

    blotch = _fbm(size, rng)                                # slow variation: uneven bluing, oily patches
    speck = rng.random((size, size)).astype(np.float32)     # fine grain
    grain = _noise(size, 64, rng)
    edge = edge[:, :, 0]
    ao = np.clip(ao[:, :, 0], 0.0, 1.0)
    scratch = _scratches(size, rng, 90)

    # bluing wears off along edges, unevenly
    wear = _smoothstep(0.15, 0.55, edge + (blotch - 0.5) * 0.5)
    cavity = 1.0 - ao

    albedo = base * (1.0 + (blotch[..., None] - 0.5) * 0.30 + (speck[..., None] - 0.5) * 0.04 + (grain[..., None] - 0.5) * 0.07)
    albedo = albedo * (1.0 - wear[..., None]) + worn * wear[..., None] * (0.85 + grain[..., None] * 0.3)
    albedo = albedo * (1.0 - cavity[..., None] * 0.45)                       # grime in the crevices
    albedo = albedo + scratch[..., None] * 0.20 * (0.4 + 0.6 * wear[..., None])
    albedo = np.clip(albedo, 0.0, 1.0)

    roughness = rough * (1.0 + (blotch - 0.5) * 0.7) + (speck - 0.5) * 0.08
    roughness = roughness * (1.0 - wear * 0.45) + cavity * 0.30 - scratch * 0.15
    roughness = np.clip(roughness, 0.12, 0.95)
    # blued steel is an oxide coat, not bare metal: partly metallic, so it keeps some diffuse light and reads as form;
    # worn edges are bare metal
    metallic = np.clip(0.76 + wear * 0.24 - cavity * 0.30 + scratch * 0.1, 0.35, 1.0)

    orm = np.stack([ao, roughness, metallic], axis=2)
    return albedo, orm


def _save(array, path, colorspace):
    size = array.shape[0]
    rgba = np.concatenate([array, np.ones((size, size, 1), dtype=np.float32)], axis=2)
    image = bpy.data.images.new(os.path.basename(path), size, size, alpha=False)
    image.colorspace_settings.name = colorspace
    image.pixels.foreach_set(rgba.astype(np.float32).reshape(-1))
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    return bpy.data.images.load(path)


# ---------------------------------------------------------------------------------------------------------- merge

def _final_material(albedo_image, orm_image, name):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = albedo_image
    albedo.interpolation = "Closest"
    albedo_image.colorspace_settings.name = "sRGB"
    orm = nodes.new("ShaderNodeTexImage")
    orm.image = orm_image
    orm.interpolation = "Closest"
    orm_image.colorspace_settings.name = "Non-Color"
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(albedo.outputs["Color"], shader.inputs["Base Color"])
    links.new(orm.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], shader.inputs["Roughness"])      # glTF: green = roughness, blue = metallic
    links.new(split.outputs["Blue"], shader.inputs["Metallic"])
    return mat


def _merge_slots(objects, metal_mats, final):
    """One slot for all the metal, so the mesh has one surface (one draw call) for it instead of one per colour."""
    for ob in objects:
        me = ob.data
        old = list(me.materials)
        new = []
        mapping = []
        for mat in old:
            target = final if mat in metal_mats else mat
            if target not in new:
                new.append(target)
            mapping.append(new.index(target))
        indices = [mapping[poly.material_index] for poly in me.polygons]
        me.materials.clear()                       # clearing the slots resets every face to slot 0, so set them after
        for mat in new:
            me.materials.append(mat)
        for poly, index in zip(me.polygons, indices):
            poly.material_index = index


# ----------------------------------------------------------------------------------------------------------- main

def texture_metal(objects, metal_mats, out_dir, name, size=256, seed=7, island_margin=0.012, edge_radius=0.005):
    metal_mats = list(metal_mats)
    scene = bpy.context.scene
    engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = False
    world = bpy.data.worlds.new("BakeWorld")
    scene.world = world
    try:
        world.light_settings.distance = 0.05                   # occlusion only from things this close, in metres
    except AttributeError:
        pass

    _unwrap(objects, metal_mats, island_margin)
    ids = _bake(objects, metal_mats, "ids", size)
    edge = _bake(objects, metal_mats, "edge", size, edge_radius)
    ao = _bake(objects, metal_mats, "ao", size)
    albedo, orm = _paint(ids, edge, ao, size, seed)

    os.makedirs(out_dir, exist_ok=True)
    albedo_image = _save(albedo, os.path.join(out_dir, f"{name}_albedo.png"), "sRGB")
    orm_image = _save(orm, os.path.join(out_dir, f"{name}_orm.png"), "Non-Color")
    final = _final_material(albedo_image, orm_image, "GunMetal")
    _merge_slots(objects, metal_mats, final)

    scene.render.engine = engine
    return final
