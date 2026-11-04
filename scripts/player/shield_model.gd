extends RefCounted

# The shield model: a round buckler (models/player_shield, built by tools/assetgen/player_shield.py). The front, which
# faces enemies, has stepped rings rising to a faceted dome with the gem on top; the back, which the player sees while
# holding it, has six ribs round a hub with its own neon ring and gem, so the state colours still show on your side.
# build() returns a Node3D whose front points along +Y (the same orientation the old disc had).
# The root carries the meta "mats" = {body, rim, gem}: the materials the shield script recolours for its states.
#
# The body is drawn unshaded with flat shading baked into its vertex colours, in a few steps (PSX style), so the shield
# looks the same in a dark corridor as in the open. Both faces are lit as if from the side you look at.

const MODEL: PackedScene = preload("res://models/player_shield/player_shield.glb")
const SHADE_STEPS := 3.0
const LIGHT_DIRECTION := Vector3(0.45, 0.8, 0.4)

# Screen colours for the body materials in the model, by glTF material name
const BODY_COLORS := {
	"Body": Color(0.2, 0.25, 0.42),
	"BodyLight": Color(0.3, 0.36, 0.55),
}

static var _mesh: ArrayMesh                 # the model's mesh with the body shading baked in, shared by every build
static var _surface_kinds: Array[String] = []   # "body", "rim" or "gem" for each surface of _mesh


static func build() -> Node3D:
	var root := Node3D.new()
	var mats := {}
	root.set_meta("mats", mats)

	var body := StandardMaterial3D.new()
	body.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.vertex_color_use_as_albedo = true
	body.vertex_color_is_srgb = true     # the body colours are picked as screen colours
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


# Copies the model's mesh once, baking the stepped flat shading into the body surfaces' vertex colours
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
		if kind == "body":
			arrays[Mesh.ARRAY_COLOR] = _shade(arrays[Mesh.ARRAY_NORMAL], BODY_COLORS.get(material_name, BODY_COLORS["Body"]))
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


# One brightness per face (the model is flat shaded, so each vertex carries its face's normal), snapped to a few steps.
# Faces on the back are lit from the back, so the side the player looks at is never left in the dark.
static func _shade(normals: PackedVector3Array, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(normals.size())
	var light := LIGHT_DIRECTION.normalized()
	for i in normals.size():
		var n := normals[i]
		var l := light if n.y >= 0.0 else Vector3(light.x, -light.y, light.z)
		var lit := clampf(n.dot(l) * 0.5 + 0.5, 0.0, 1.0)
		lit = floorf(lit * SHADE_STEPS + 0.5) / SHADE_STEPS
		var shaded := color * (0.45 + 0.75 * lit)
		shaded.a = 1.0
		colors[i] = shaded
	return colors
