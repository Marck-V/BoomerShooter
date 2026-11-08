extends RefCounted

# The shield model: a round buckler (models/player_shield, built by tools/assetgen/player_shield.py). The front, which
# faces enemies, has stepped rings rising to a faceted dome with the gem on top; the back, which the player sees while
# holding it, has six ribs round a hub with its own neon ring and gem, so the state colours still show on your side.
# build() returns a Node3D whose front points along +Y (the same orientation the old disc had).
# The root carries the meta "mats" = {body, rim, gem}: the materials the shield script recolours for its states.
#
# The body is lit like the guns, so it picks up the level's light and reflections: a colour map plus a packed
# occlusion/roughness/metallic map (red/green/blue), the same way the gun models are done. The rim and gem are unshaded
# glows, so the state colours always read.

const MODEL: PackedScene = preload("res://models/player_shield/player_shield.glb")
# The body's pictures: battle-scarred black steel. Each is three pictures side by side: the front plate, the back plate
# (no circle lines, never damaged) and the smooth, slightly lighter trim for the ribs, hub, studs and walls
# (tools/assetgen/shield_concepts.py --bake paints them; player_shield.py maps the body's faces onto them)
const BODY_TEXTURE: Texture2D = preload("res://models/player_shield/shield_body_albedo.png")
const BODY_ORM: Texture2D = preload("res://models/player_shield/shield_body_orm.png")

static var _mesh: ArrayMesh                 # the model's mesh, shared by every build
static var _surface_kinds: Array[String] = []   # "body", "rim" or "gem" for each surface of _mesh


static func build() -> Node3D:
	var root := Node3D.new()
	var mats := {}
	root.set_meta("mats", mats)

	var body := StandardMaterial3D.new()
	body.albedo_texture = BODY_TEXTURE
	body.ao_enabled = true
	body.ao_texture = BODY_ORM
	body.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	body.roughness = 1.0                 # the maps set these; the values scale them
	body.roughness_texture = BODY_ORM
	body.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	body.metallic = 1.0
	body.metallic_texture = BODY_ORM
	body.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	# Smooth and mipmapped: the retro look comes from the screen filter, so the texture can keep its detail
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats["body"] = body

	var rim := StandardMaterial3D.new()
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.albedo_color = Color(2.6, 1.9, 0.3)
	mats["rim"] = rim

	var gem := StandardMaterial3D.new()
	gem.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gem.albedo_color = Color(0.4, 2.0, 2.6)
	mats["gem"] = gem

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _get_mesh()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in _surface_kinds.size():
		mesh_instance.set_surface_override_material(i, mats[_surface_kinds[i]])
	root.add_child(mesh_instance)
	return root


# Copies the model's mesh once and sorts its surfaces into body, rim and gem by their glTF material names
static func _get_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var source := _find_mesh(MODEL.instantiate())
	_mesh = ArrayMesh.new()
	_surface_kinds.clear()
	for i in source.get_surface_count():
		var arrays := source.surface_get_arrays(i)
		var material_name := source.surface_get_material(i).resource_name if source.surface_get_material(i) else ""
		var kind := "body"
		if material_name == "Rim":
			kind = "rim"
		elif material_name == "Gem":
			kind = "gem"
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_surface_kinds.append(kind)
	return _mesh


static func _find_mesh(scene_root: Node) -> Mesh:
	var found: Mesh = null
	for node in scene_root.find_children("*", "MeshInstance3D", true, false):
		found = (node as MeshInstance3D).mesh
		break
	scene_root.free()
	return found
