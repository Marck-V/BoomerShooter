extends Area3D

# A TrenchBroom trigger volume (entity "checkpoint"). The first time the player walks through it their progress is
# saved, and dying sends them back here instead of to the start of the level (see Checkpoints).
# Stretch it across a corridor or doorway the player has to go through, so it can't be missed, and keep it thinner
# along the way they walk than across. Keep it clear of wave_triggers: the player comes back standing on the floor
# below its middle.
#
# The look, built in code from the volume's size: a curtain of neon scanlines across the corridor. Cyan until it's
# reached, then it flashes, ripples out from where the player crossed and settles to a dim green.

const CURTAIN_SHADER: Shader = preload("res://shaders/environment/checkpoint_curtain.gdshader")
const SOUND := "assets/audio/sfx/ui/accepter.mp3"

const IDLE_COLOR := Color(0.2, 0.9, 1.0)
const REACHED_COLOR := Color(0.3, 1.0, 0.4)
const FLOOR_SEARCH_DEPTH := 50.0
const REACH_TIME := 0.9
const PLAYER_CHEST := 1.2   # above the player's origin: where the ripple starts

var bounds: AABB   # of the volume, in local space
var curtain: MeshInstance3D
var curtain_material: ShaderMaterial
var reach_tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# The map build positions the node and adds its collision shapes right after adding it
	_build_curtain.call_deferred()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and Checkpoints.reach(self, get_spawn_point()):
		Audio.play(SOUND)
		_play_reached(body.global_position + Vector3.UP * PLAYER_CHEST)


# The floor below the middle of the volume, or the middle itself if there is none
func get_spawn_point() -> Vector3:
	var hit := PhysicsLayers.surface_ray(get_tree(), global_position, global_position + Vector3.DOWN * FLOOR_SEARCH_DEPTH)
	return hit["position"] if not hit.is_empty() else global_position


func _volume_bounds() -> AABB:
	var result := AABB()
	var first := true
	for node in find_children("*", "CollisionShape3D", false, false):
		var shape_node := node as CollisionShape3D
		var convex := shape_node.shape as ConvexPolygonShape3D
		if convex == null:
			continue
		for point in convex.points:
			var local := shape_node.transform * point
			if first:
				result = AABB(local, Vector3.ZERO)
				first = false
			else:
				result = result.expand(local)
	return result


# Across the corridor's long side, halfway along its short one
func _build_curtain() -> void:
	if not is_inside_tree():
		return   # removed (or replaced by the map build) before the deferred call ran
	bounds = _volume_bounds()
	var along_x := bounds.size.x >= bounds.size.z
	var width := bounds.size.x if along_x else bounds.size.z
	var height := bounds.size.y

	curtain_material = ShaderMaterial.new()
	curtain_material.shader = CURTAIN_SHADER
	curtain_material.set_shader_parameter("size", Vector2(width, height))
	curtain_material.set_shader_parameter("idle_color", IDLE_COLOR)
	curtain_material.set_shader_parameter("reached_color", REACHED_COLOR)
	# Reached before the checkpoint the player came back to: show it already lit up
	curtain_material.set_shader_parameter("reached", 1.0 if Checkpoints.is_reached(self) else 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	curtain = MeshInstance3D.new()
	curtain.mesh = quad
	curtain.material_override = curtain_material
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain.position = bounds.get_center()
	if not along_x:
		curtain.rotation.y = PI * 0.5
	add_child(curtain)


# Flash, a ripple out from where the player crossed, then settle on the reached colour
func _play_reached(crossing: Vector3) -> void:
	if curtain_material == null:
		return
	var local := curtain.to_local(crossing)
	var size: Vector2 = curtain_material.get_shader_parameter("size")
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y).clamp(Vector2.ZERO, Vector2.ONE)
	curtain_material.set_shader_parameter("ripple_center", uv)

	if reach_tween:
		reach_tween.kill()
	reach_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	reach_tween.tween_method(func(r: float): curtain_material.set_shader_parameter("reached", r), 0.0, 1.0, REACH_TIME)
	reach_tween.tween_method(func(r: float): curtain_material.set_shader_parameter("ripple_radius", r),
		0.0, maxf(size.x, size.y) * 1.2, REACH_TIME)
	reach_tween.tween_method(func(f: float): curtain_material.set_shader_parameter("flash", f), 2.0, 0.0, REACH_TIME * 0.7)
	reach_tween.chain().tween_callback(func(): curtain_material.set_shader_parameter("ripple_radius", -1.0))
