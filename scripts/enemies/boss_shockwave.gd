extends Node3D
class_name BossShockwave

# A shockwave racing outwards along the floor from the boss. Anyone standing on the ground when the front
# passes is hit and thrown back; jumping (or being in the air some other way) clears it. A glowing wall rises
# from the front and a ring of heat marks it on the floor. Built in code and added to the level.
#   BossShockwave.spawn(tree, center, max_radius, speed, damage)               the slam: hurts
#   BossShockwave.spawn(tree, center, max_radius, speed, 0.0, true)             a push only: a phase change

const RING_SHADER: Shader = preload("res://shaders/boss_shockwave.gdshader")
const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")

const START_RADIUS := 1.5
const BAND := 1.3                  # half thickness of the lethal band, meters
const CLEARANCE := 0.8             # feet higher than this above the floor are over the wave
const WALL_HEIGHT := 1.4
const FLOOR_LIFT := 0.07

var max_radius := 22.0
var speed := 14.0
var damage := 40.0
var push_speed := 20.0
var push_only := false
var floor_y := 0.0
var radius := START_RADIUS
var struck := {}                   # players already hit by this wave
var ring_material: ShaderMaterial
var wall: MeshInstance3D
var wall_material: StandardMaterial3D
var light: OmniLight3D
var finishing := false


static func spawn(tree: SceneTree, center: Vector3, max_radius: float, speed: float, damage: float, push_only := false) -> BossShockwave:
	var wave := BossShockwave.new()
	wave.max_radius = max_radius
	wave.speed = speed
	wave.damage = damage
	wave.push_only = push_only
	tree.current_scene.add_child(wave)
	wave.global_position = center
	wave.floor_y = center.y
	return wave


func _ready() -> void:
	var color := Color(0.55, 0.75, 1.0) if push_only else Color(1.0, 0.4, 0.1)

	# The ring on the floor
	ring_material = ShaderMaterial.new()
	ring_material.shader = RING_SHADER
	ring_material.set_shader_parameter("color", color)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * max_radius * 2.0
	var ring := MeshInstance3D.new()
	ring.mesh = plane
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = FLOOR_LIFT
	add_child(ring)

	# The wall of energy at the front
	wall_material = StandardMaterial3D.new()
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_material.albedo_color = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, 0.45)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = WALL_HEIGHT
	cylinder.radial_segments = 48
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	wall = MeshInstance3D.new()
	wall.mesh = cylinder
	wall.material_override = wall_material
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = WALL_HEIGHT * 0.5
	add_child(wall)

	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.position.y = 1.0
	add_child(light)
	_update_visuals()


func _physics_process(delta: float) -> void:
	if finishing:
		return
	radius += speed * delta
	_update_visuals()
	_check_players()
	if radius >= max_radius:
		_finish()


func _update_visuals() -> void:
	ring_material.set_shader_parameter("ring_radius", clampf(radius / max_radius, 0.0, 1.0))
	wall.scale = Vector3(radius, 1.0, radius)
	# Weaker towards the edge of its reach
	var strength := clampf(1.0 - radius / max_radius, 0.0, 1.0)
	wall_material.albedo_color.a = 0.15 + 0.4 * strength
	light.position = Vector3(0.0, 1.0, 0.0)
	light.light_energy = 1.0 + 2.5 * strength


func _check_players() -> void:
	for node in get_tree().get_nodes_in_group("Player"):
		var player := node as Node3D
		if player == null or struck.has(player):
			continue
		var offset := player.global_position - global_position
		var flat := Vector2(offset.x, offset.z)
		if absf(flat.length() - radius) > BAND:
			continue
		struck[player] = true
		if player.global_position.y - floor_y > CLEARANCE:
			continue  # jumped it
		var away := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 0.01 else Vector3.BACK
		if player.has_method("apply_push"):
			player.apply_push(away * push_speed)
		if player.has_method("apply_camera_kick"):
			player.apply_camera_kick(0.06, randf_range(-0.03, 0.03))
		if not push_only and player.has_method("damage"):
			player.damage(damage)
		ImpactParticles.spawn(get_tree(), player.global_position + Vector3.UP * 0.2, Vector3.UP, 1.4)


func _finish() -> void:
	finishing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(v): ring_material.set_shader_parameter("fade", v), 1.0, 0.0, 0.3)
	tween.tween_property(wall_material, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)
