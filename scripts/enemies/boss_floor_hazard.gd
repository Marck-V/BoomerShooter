extends Node3D
class_name BossFloorHazard

# A set of floor tiles that light up, flash as a warning and then burn: anyone standing on the ground in a
# burning tile takes damage over and over until it fades. Jumping clears a tick (feet above CLEARANCE).
#   BossFloorHazard.spawn(tree, [Vector3 floor centre, ...], cell_size, damage, warn_time, burn_time)

const SHADER: Shader = preload("res://shaders/boss_hazard_tile.gdshader")
const CLEARANCE := 0.8
const TICK_TIME := 0.4
const FLOOR_LIFT := 0.07
const FADE_TIME := 0.3

var cells: Array = []              # floor-level centres of the tiles
var cell_size := 4.0
var damage := 20.0
var warn_time := 1.4
var burn_time := 1.3
var elapsed := 0.0
var burning := false
var finishing := false
var tick_left := {}                # player -> time until it can be hurt again
var materials: Array[ShaderMaterial] = []
var light: OmniLight3D


static func spawn(tree: SceneTree, floor_cells: Array, size: float, tick_damage: float, warn: float, burn: float) -> BossFloorHazard:
	var hazard := BossFloorHazard.new()
	hazard.cells = floor_cells
	hazard.cell_size = size
	hazard.damage = tick_damage
	hazard.warn_time = warn
	hazard.burn_time = burn
	tree.current_scene.add_child(hazard)
	return hazard


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(cell_size * 0.96, cell_size * 0.96)
	var centre := Vector3.ZERO
	for cell in cells:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		var tile := MeshInstance3D.new()
		tile.mesh = plane
		tile.material_override = material
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tile)
		tile.global_position = Vector3(cell.x, cell.y + FLOOR_LIFT, cell.z)
		materials.append(material)
		centre += cell
	if cells.size() > 0:
		centre /= float(cells.size())
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.1)
	light.omni_range = cell_size * 2.5
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	light.global_position = centre + Vector3.UP * 1.0


func _physics_process(delta: float) -> void:
	elapsed += delta
	if finishing:
		return
	if not burning:
		var progress := clampf(elapsed / warn_time, 0.0, 1.0)
		for material in materials:
			material.set_shader_parameter("progress", progress)
		light.light_energy = 0.6 * progress
		if elapsed >= warn_time:
			burning = true
			for material in materials:
				material.set_shader_parameter("active", 1.0)
			light.light_energy = 3.0
	else:
		_hurt_players(delta)
		if elapsed >= warn_time + burn_time:
			_finish()


func _hurt_players(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("Player"):
		var player := node as Node3D
		if player == null:
			continue
		tick_left[player] = float(tick_left.get(player, 0.0)) - delta
		if tick_left[player] > 0.0:
			continue
		var cell = _cell_under(player.global_position)
		if cell == null:
			continue
		if player.global_position.y - float(cell.y) > CLEARANCE:
			continue
		tick_left[player] = TICK_TIME
		if player.has_method("damage"):
			player.damage(damage)
		if player.has_method("apply_camera_kick"):
			player.apply_camera_kick(0.03, randf_range(-0.015, 0.015))


func _cell_under(point: Vector3):
	var half := cell_size * 0.5
	for cell in cells:
		if absf(point.x - cell.x) <= half and absf(point.z - cell.z) <= half:
			return cell
	return null


func _finish() -> void:
	finishing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(v): for material in materials: material.set_shader_parameter("fade", v), 1.0, 0.0, FADE_TIME)
	tween.tween_property(light, "light_energy", 0.0, FADE_TIME)
	tween.chain().tween_callback(queue_free)
