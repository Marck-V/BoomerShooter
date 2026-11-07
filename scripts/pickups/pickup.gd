extends Node3D
class_name BasePickup

@export_enum("Health", "Ammo", "Points") var type: String
@export_category("Weapon Type") 
@export_enum("pistol","shotgun","rifle","flamethrower","lightning") var weapon_id: String ## Only assign this if this is an Ammo pickup
@export_category("Variables")
@export var points_amount = 500
@export var healing_amount = 25
@export var ammo_amount = 100
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

var model_scale = Vector3.ONE
var gold_bar_scale_factor = 0.1
var health_scale_factor = 0.35   # the medkit is about 2 m across in its model: about 0.7 m here
var ammo_scale = 2

var player_inside := false   # the player is standing in this pickup (only tracked for medkits)
var base_y = 0.0
var t = 0.0

var ammo_paths = {
	"pistol": "res://models/weapons/pistol_ammo_mesh.tscn",
	"shotgun": "res://models/weapons/shotgun_ammo_mesh.tscn",
	"rifle": "res://models/weapons/rifle_ammo_mesh.tscn",
	"flamethrower": "res://models/weapons/flamethrower_ammo.glb",   # the gas canister from the flamethrower's model
	"lightning": ""   # built in code: one of the gun's glass vials, see _make_vial()
}

# Weapons that borrow another weapon's ammo model get it tinted in their colour (none do at the moment)
var ammo_tints = {}

# The halo behind an ammo pickup, where it should not be the usual orange
var ammo_halos = {
	"lightning": Color(0.2, 0.5, 1.0, 0.55)
}

var model_paths = {
	"Health": "res://scenes/props/medkit.tscn",
	"Points" : "res://scenes/props/psx_gold_bar.tscn"
}

var scale_map = {
	"Health": Vector3(health_scale_factor, health_scale_factor, health_scale_factor),
	"Ammo": Vector3(ammo_scale, ammo_scale, ammo_scale),
	"Points": Vector3(gold_bar_scale_factor, gold_bar_scale_factor, gold_bar_scale_factor)
}

var glow_colors = {
	"Health": Color(0.2, 1.0, 0.35),
	"Ammo": Color(1.0, 0.7, 0.2),
	"Points": Color(1.0, 0.85, 0.2)
}

var model_instance: Node3D
var glow_instance: MeshInstance3D


func _ready() -> void:
	$Area3D.body_exited.connect(_on_area_3d_body_exited)
	mesh_instance_3d.visible = false
	base_y = position.y
	_build_model()


# Pickups placed from a map entity get their properties (type, weapon_id...) after _ready has already run,
# so the model is rebuilt then; otherwise every map pickup would show the scene's default type.
func _func_godot_apply_properties(_properties: Dictionary) -> void:
	if is_node_ready():
		_build_model()


func _build_model() -> void:
	if model_instance:
		model_instance.queue_free()
		model_instance = null
	if type == "Ammo" and weapon_id == "lightning":
		model_instance = _make_vial()
	else:
		var model_scene
		if type == "Ammo":
			model_scene = load(ammo_paths[weapon_id]) if ammo_paths.has(weapon_id) else load(ammo_paths["shotgun"])
		else:
			model_scene = load(model_paths[type]) if model_paths.has(type) else load(model_paths["Points"])
		model_instance = model_scene.instantiate()
	model_instance.scale = scale_map.get(type, scale_map["Points"])
	if type == "Ammo" and ammo_tints.has(weapon_id):
		_tint(model_instance, ammo_tints[weapon_id])
	add_child(model_instance)
	_build_glow()


# ---------------------------
# Lightning ammo: one of the glass vials from the side of the lightning gun
# ---------------------------
# A glass tube between two copper caps, a nub on each end and a jagged arc inside, standing upright. The proportions
# are the gun's vial's, scaled up. One mesh with three surfaces (copper, glass, arc) is built once and shared by every
# lightning pickup, so each one costs three draw calls and no extra memory.
const VIAL_RADIUS := 0.038
const VIAL_HALF := 0.095            # half the length of the glass
const VIAL_CAP_RADIUS := 0.0455
const VIAL_CAP_LENGTH := 0.036
const VIAL_NUB_RADIUS := 0.02
const VIAL_ARC_SEED := 11

static var vial_mesh: ArrayMesh


func _make_vial() -> Node3D:
	if vial_mesh == null:
		vial_mesh = _build_vial_mesh()
	var root := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = vial_mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	return root


static func _build_vial_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var copper := SurfaceTool.new()
	copper.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := CylinderMesh.new()
	cap.top_radius = VIAL_CAP_RADIUS
	cap.bottom_radius = VIAL_CAP_RADIUS
	cap.height = VIAL_CAP_LENGTH
	cap.radial_segments = 12
	cap.rings = 1
	var nub := SphereMesh.new()
	nub.radius = VIAL_NUB_RADIUS
	nub.height = VIAL_NUB_RADIUS * 2.0
	nub.radial_segments = 6
	nub.rings = 3
	for end in [-1.0, 1.0]:
		copper.append_from(cap, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, end * (VIAL_HALF + VIAL_CAP_LENGTH * 0.5), 0.0)))
		copper.append_from(nub, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, end * (VIAL_HALF + VIAL_CAP_LENGTH + VIAL_NUB_RADIUS * 0.6), 0.0)))
	copper.commit(mesh)
	var copper_material := StandardMaterial3D.new()
	copper_material.albedo_color = Color(0.93, 0.55, 0.30)
	copper_material.metallic = 0.5
	copper_material.roughness = 0.4
	mesh.surface_set_material(0, copper_material)

	var glass := CylinderMesh.new()
	glass.top_radius = VIAL_RADIUS
	glass.bottom_radius = VIAL_RADIUS
	glass.height = VIAL_HALF * 2.0
	glass.radial_segments = 12
	glass.rings = 1
	glass.cap_top = true
	glass.cap_bottom = true
	var glass_arrays := glass.get_mesh_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass_arrays)
	var glass_material := StandardMaterial3D.new()
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass_material.albedo_color = Color(0.5, 0.75, 1.0, 0.2)
	glass_material.roughness = 0.05
	glass_material.emission_enabled = true
	glass_material.emission = Color(0.5, 0.75, 1.0)
	glass_material.emission_energy_multiplier = 0.3
	mesh.surface_set_material(1, glass_material)

	var arc := SurfaceTool.new()
	arc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = VIAL_ARC_SEED
	var inner := VIAL_HALF - 0.004
	_add_bolt(arc, Vector3(0.0, -inner, 0.0), Vector3(0.0, inner, 0.0), rng, 7, 0.22, 0.0045)
	for i in 2:
		var y := rng.randf_range(-VIAL_HALF * 0.5, VIAL_HALF * 0.5)
		var side := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		_add_bolt(arc, Vector3(0.0, y, 0.0), Vector3(0.0, y, 0.0) + side * (VIAL_RADIUS - 0.006), rng, 3, 0.3, 0.003)
	arc.generate_normals()
	arc.commit(mesh)
	var arc_material := StandardMaterial3D.new()
	arc_material.albedo_color = Color(0.2, 0.5, 1.0)
	arc_material.emission_enabled = true
	arc_material.emission = Color(0.2, 0.5, 1.0)
	arc_material.emission_energy_multiplier = 1.6
	mesh.surface_set_material(2, arc_material)
	return mesh


# A jagged arc from `from` to `to`: thin square rods end to end, kinked sideways between the two
static func _add_bolt(tool: SurfaceTool, from: Vector3, to: Vector3, rng: RandomNumberGenerator, kinks: int, jitter: float, radius: float) -> void:
	var span := to - from
	var side := span.cross(Vector3.RIGHT if absf(span.normalized().x) < 0.9 else Vector3.UP).normalized()
	var up := span.cross(side).normalized()
	var points: Array[Vector3] = [from]
	for k in range(1, kinks):
		var t := float(k) / kinks
		var wiggle := span.length() * jitter * sin(PI * t)
		points.append(from + span * t + side * rng.randf_range(-1.0, 1.0) * wiggle + up * rng.randf_range(-1.0, 1.0) * wiggle)
	points.append(to)
	for i in points.size() - 1:
		_add_rod(tool, points[i], points[i + 1], radius)


static func _add_rod(tool: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized() * radius
	var w := axis.cross(u).normalized() * radius
	var ring_a: Array[Vector3] = [a + u + w, a - u + w, a - u - w, a + u - w]
	var ring_b: Array[Vector3] = [b + u + w, b - u + w, b - u - w, b + u - w]
	for i in 4:
		var j := (i + 1) % 4
		for vertex in [ring_a[i], ring_b[i], ring_b[j], ring_a[i], ring_b[j], ring_a[j]]:
			tool.add_vertex(vertex)


# Soft camera-facing halo behind the model, tinted by pickup type
func _build_glow() -> void:
	if glow_instance:
		glow_instance.queue_free()
	var color: Color = glow_colors.get(type, glow_colors["Points"])
	if type == "Ammo" and ammo_halos.has(weapon_id):
		color = ammo_halos[weapon_id]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pickups/pickup_glow.gdshader")
	mat.set_shader_parameter("glow_color", color)
	mat.render_priority = -1
	var quad := QuadMesh.new()
	var bounds := _model_bounds()
	var glow_size: float = clamp(bounds.size.length() * 1.2, 0.9, 1.5)
	quad.size = Vector2(glow_size, glow_size)
	quad.material = mat
	glow_instance = MeshInstance3D.new()
	glow_instance.mesh = quad
	glow_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_instance.position = bounds.get_center()
	add_child(glow_instance)


# Bounds of the visible model in the pickup's local space, so the glow sits on the model's center
func _model_bounds() -> AABB:
	var result := AABB()
	var first := true
	for node in model_instance.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := model_instance.transform
		var n: Node = mi
		var chain: Array[Transform3D] = []
		while n != model_instance:
			chain.append((n as Node3D).transform)
			n = n.get_parent()
		for i in range(chain.size() - 1, -1, -1):
			xf = xf * chain[i]
		var box := xf * mi.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _tint(root: Node, color: Color) -> void:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.albedo_color = color
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = overlay


func _process(delta):
	t += delta

	# A medkit walked over at full health is left alone: only while the player is standing in it (tracked by the
	# area's enter and exit signals) does it wait to be needed, so nothing runs for the medkits the player is not on
	if type == "Health" and player_inside and GlobalVariables.player and GlobalVariables.player.health < 100:
		_on_area_3d_body_entered(GlobalVariables.player)
		return

	rotate_y(0.5 * delta)
	position.y = base_y + sin(t) * 0.1
	rotation.x = sin(t * 1.3) * 0.05
	rotation.z = sin(t * 1.7) * 0.05
	
func _on_area_3d_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
	player_inside = true
		
	match type:
		"Ammo":
			GlobalVariables.add_ammo(weapon_id, ammo_amount)
			Audio.play("assets/audio/sfx/weapons/reload.mp3")
		"Health":
			# Already at full health: a medkit would be wasted, so it stays where it is for later
			if body.health >= 100:
				return
			GlobalVariables.add_health(healing_amount)
			if body.has_method("play_heal_flash"):
				body.play_heal_flash()
			Audio.play("assets/audio/sfx/pickups/health_pickup.mp3")
		"Points":
			GlobalVariables.add_points(points_amount)
			Audio.play("assets/audio/sfx/pickups/money_pickup.mp3")

	Checkpoints.mark_gone(self)
	queue_free()


func _on_area_3d_body_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_inside = false
