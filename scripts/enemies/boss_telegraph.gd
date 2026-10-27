extends Node3D
class_name BossTelegraph

# A warning the boss paints on the floor before an attack, so the player can read what is about to happen and
# where. A circle for area attacks (the shockwave slam) or a lane for a rush (the charge). Added to the level,
# not to the boss, so the boss's own scale doesn't stretch it. It fills as the attack gets close:
#   var warning := BossTelegraph.circle(tree, center, radius)
#   warning.set_progress(0.5)  ...  warning.finish()

const SHADER: Shader = preload("res://shaders/boss_telegraph.gdshader")
const FLOOR_LIFT := 0.06     # just above the floor, so it never z-fights with it

var material: ShaderMaterial
var plane: MeshInstance3D
var fade_tween: Tween
var strength := 1.0


# A filled circle on the floor
static func circle(tree: SceneTree, center: Vector3, radius: float, color := Color(1.0, 0.25, 0.1)) -> BossTelegraph:
	var warning := BossTelegraph.new()
	tree.current_scene.add_child(warning)
	warning._build(0, color)
	warning.plane.mesh = _plane(Vector2.ONE * 2.0 * radius)
	warning.global_position = center + Vector3.UP * FLOOR_LIFT
	return warning


# A lane on the floor from `from` towards `to`, `width` wide
static func lane(tree: SceneTree, from: Vector3, to: Vector3, width: float, color := Color(1.0, 0.25, 0.1)) -> BossTelegraph:
	var warning := BossTelegraph.new()
	tree.current_scene.add_child(warning)
	warning._build(1, color)
	warning.set_lane(from, to, width)
	return warning


static func _plane(size: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	return mesh


func _build(mode: int, color: Color) -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("color", color)
	plane = MeshInstance3D.new()
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plane)


# Re-aims a lane (the charge keeps pointing at the player while it winds up)
func set_lane(from: Vector3, to: Vector3, width: float) -> void:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := maxf(flat.length(), 0.1)
	plane.mesh = _plane(Vector2(width, length))
	global_position = Vector3((from.x + to.x) * 0.5, from.y + FLOOR_LIFT, (from.z + to.z) * 0.5)
	global_rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)


func set_progress(value: float) -> void:
	material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


# Fades out and removes itself
func finish(fade_time := 0.2) -> void:
	if fade_tween != null and fade_tween.is_valid():
		return
	fade_tween = create_tween()
	fade_tween.tween_method(func(v): material.set_shader_parameter("strength", v), 1.0, 0.0, fade_time)
	fade_tween.tween_callback(queue_free)
