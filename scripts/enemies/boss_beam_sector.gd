extends Node3D
class_name BossBeamSector

# A wedge of fire that shoots up out of the floor, like the columns the robot boss's floor hazard raises
# (boss_floor_hazard.gd, same shader): it surges outward from the point it fans out from, burns for a moment, then
# fades. Anyone on the ground inside the part that has reached them takes damage again and again while it burns;
# jumping clears a tick (feet higher than CLEARANCE).
#   BossBeamSector.spawn(tree, center, direction, radius, half_angle, tick_damage, burn_time, surge_speed)

const BEAM_SHADER: Shader = preload("res://shaders/boss/boss_hazard_beam.gdshader")
const HEIGHT := 14.0
const CLEARANCE := 0.8
const TICK_TIME := 0.4
const FADE_TIME := 0.3
const ARC_STEPS := 8

var center := Vector3.ZERO
var direction := Vector3.FORWARD
var radius := 20.0
var half_angle := 0.3
var damage := 14.0
var burn_time := 1.0
var surge_speed := 60.0
var elapsed := 0.0
var tick_left := 0.0
var finishing := false
var material: ShaderMaterial


static func spawn(tree: SceneTree, from: Vector3, along: Vector3, length: float, half: float, tick_damage: float, burn: float, surge: float) -> BossBeamSector:
	var beam := BossBeamSector.new()
	beam.center = from
	beam.direction = along
	beam.radius = length
	beam.half_angle = half
	beam.damage = tick_damage
	beam.burn_time = burn
	beam.surge_speed = surge
	tree.current_scene.add_child(beam)
	return beam


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = BEAM_SHADER
	material.set_shader_parameter("height", HEIGHT)
	material.set_shader_parameter("radius", 0.01)      # the camera fade is done by `inside` instead (see _update_inside)
	material.set_shader_parameter("flash", 0.8)
	material.set_shader_parameter("streaks", 5.0)
	material.set_shader_parameter("intensity", 0.22)   # a wedge is much bigger than a tile, so its walls stack up on screen: keep them thin
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _wedge_mesh()
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	# The mesh is centred on half its height (the shader reads height from that), so lift the node by half of it.
	# Scaling the node across the floor grows the wedge outward from its point.
	global_position = center + Vector3.UP * HEIGHT * 0.5
	global_rotation = Vector3(0.0, atan2(direction.x, direction.z), 0.0)
	scale = Vector3(0.05, 1.0, 0.05)


func _physics_process(delta: float) -> void:
	elapsed += delta
	var front := minf(elapsed * surge_speed, radius)
	var grown := front / radius
	scale = Vector3(maxf(grown, 0.05), 1.0, maxf(grown, 0.05))
	if finishing:
		return
	material.set_shader_parameter("flash", move_toward(float(material.get_shader_parameter("flash")), 0.0, delta * 3.0))
	_update_inside(front)
	_hurt_players(delta, front)
	if elapsed >= burn_time:
		_finish()


# Seen from inside, the wedge's walls would blind the player, so it fades out while the camera is within it
func _update_inside(front: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	material.set_shader_parameter("inside", 1.0 if _is_inside(camera.global_position, front, 1.5) else 0.0)


func _is_inside(point: Vector3, front: float, margin := 0.0) -> bool:
	var offset := Vector3(point.x - center.x, 0.0, point.z - center.z)
	var distance := offset.length()
	if distance > front + margin:
		return false
	if distance < 1.0:
		return true
	var angle := atan2(offset.x, offset.z)
	return absf(angle_difference(angle, atan2(direction.x, direction.z))) <= half_angle + margin / maxf(distance, 1.0)


func _hurt_players(delta: float, front: float) -> void:
	tick_left -= delta
	if tick_left > 0.0:
		return
	for node in get_tree().get_nodes_in_group("Player"):
		var player := node as Node3D
		if player == null or player.global_position.y - center.y > CLEARANCE:
			continue
		if not _is_inside(player.global_position, front):
			continue
		tick_left = TICK_TIME
		if player.has_method("damage"):
			player.damage(damage, false, center)
		if player.has_method("apply_camera_kick"):
			player.apply_camera_kick(0.03, randf_range(-0.015, 0.015))


func _finish() -> void:
	finishing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(v): material.set_shader_parameter("fade", v), 1.0, 0.0, FADE_TIME)
	tween.chain().tween_callback(queue_free)


# An open-topped, open-bottomed wedge: the curved outer wall and the two flat sides, in local space with the point at
# the origin, fanning out along +Z, and its middle at y = 0. UV.x runs once round the whole outline, for the streaks.
func _wedge_mesh() -> ArrayMesh:
	var half_height := HEIGHT * 0.5
	var outline: Array[Vector2] = []     # (x, z), from the point out along one side, round the arc, and back in
	outline.append(Vector2.ZERO)
	for i in ARC_STEPS + 1:
		var angle := lerpf(-half_angle, half_angle, float(i) / ARC_STEPS)
		outline.append(Vector2(sin(angle), cos(angle)) * radius)
	outline.append(Vector2.ZERO)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := 0.0
	for i in outline.size() - 1:
		total += outline[i].distance_to(outline[i + 1])
	var walked := 0.0
	for i in outline.size() - 1:
		var a := outline[i]
		var b := outline[i + 1]
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		var along := (b - a) / length
		var normal := Vector3(along.y, 0.0, -along.x)
		var u0 := walked / total
		var u1 := (walked + length) / total
		walked += length
		var a_low := Vector3(a.x, -half_height, a.y)
		var a_high := Vector3(a.x, half_height, a.y)
		var b_low := Vector3(b.x, -half_height, b.y)
		var b_high := Vector3(b.x, half_height, b.y)
		for corner in [[a_low, u0, 1.0], [b_low, u1, 1.0], [b_high, u1, 0.0], [a_low, u0, 1.0], [b_high, u1, 0.0], [a_high, u0, 0.0]]:
			tool.set_normal(normal)
			tool.set_uv(Vector2(corner[1], corner[2]))
			tool.add_vertex(corner[0])
	return tool.commit()
