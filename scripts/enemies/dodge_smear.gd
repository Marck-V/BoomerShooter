extends Node
class_name DodgeSmear

# Whoosh for a dodging enemy. The enemy is drawn once into a small SubViewport (seen from the player's
# camera, alone on SNAPSHOT_LAYER); dodge_smear.gdshader then draws that snapshot as scan rows on a quad in
# front of the camera. The head of the smear follows the enemy as it really moves and the rows stretch back
# towards where it started, so the streak always points from the start of the dodge to where the enemy is.

const SMEAR_SHADER: Shader = preload("res://shaders/dodge_smear.gdshader")
const SNAPSHOT_LAYER := 1 << 19      # visual layer 20: only the dodging enemy is put on it, briefly
const SNAPSHOT_SCALE := 0.5          # snapshot resolution relative to the game viewport
const DURATION := 0.45
const QUAD_DISTANCE := 0.3
const ROWS_ACROSS := 18.0            # scan rows across the enemy
const ENEMY_RADIUS := 0.7            # meters, for sizing the smear on screen
const ENEMY_CENTER_HEIGHT := 0.7
const MAX_ACTIVE := 4
const OCCLUSION_MASK := 1 | 2        # level geometry: a smear never shows an enemy that is behind a wall

signal snapshot_ready  # the enemy has been drawn into the snapshot, so it can safely be hidden

static var active_count := 0

var camera: Camera3D
var snapshot_viewport: SubViewport
var quad: MeshInstance3D
var material: ShaderMaterial
var follow_enemy: Node3D
var head_world := Vector3.ZERO     # where the head of the smear is: the enemy's live position
var stretch_max := 2.0
var dodge_time := 0.35
var viewport_size := Vector2.ONE
var half_extent := 0.1
var elapsed := 0.0
var started := false


# Dodge start: leaves the smear behind (if the player can see the enemy) and hides the enemy until the dodge ends.
# The enemy has to be drawn into the snapshot first, so hiding waits for it.
static func vanish(enemy: EnemyBase, motion_dir: Vector3) -> void:
	enemy.is_dodging = true
	var smear := play(enemy, motion_dir)
	if smear != null:
		await smear.snapshot_ready
	if is_instance_valid(enemy) and enemy.is_dodging:
		enemy.set_dodge_vanished(true)


static func play(enemy: Node3D, motion_dir: Vector3) -> DodgeSmear:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or active_count >= MAX_ACTIVE:
		return null
	if motion_dir.length() < 0.01:
		return null
	var view_camera := enemy.get_viewport().get_camera_3d()
	if view_camera == null:
		return null
	var center := enemy.global_position + Vector3.UP * ENEMY_CENTER_HEIGHT
	if not view_camera.is_position_in_frustum(center):
		return null
	var query := PhysicsRayQueryParameters3D.create(view_camera.global_position, center)
	query.collision_mask = OCCLUSION_MASK
	if not enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return null

	var effect := DodgeSmear.new()
	enemy.get_tree().root.add_child(effect)
	effect._start(enemy, view_camera, center, motion_dir.normalized())
	return effect


func _start(enemy: Node3D, view_camera: Camera3D, center: Vector3, motion_dir: Vector3) -> void:
	active_count += 1
	camera = view_camera
	follow_enemy = enemy
	head_world = center
	var view := camera.get_viewport()
	var full_size: Vector2 = view.get_visible_rect().size
	viewport_size = full_size

	# Snapshot: the same view as the player's camera, with only this enemy visible, on a transparent background
	snapshot_viewport = SubViewport.new()
	snapshot_viewport.size = Vector2i((full_size * SNAPSHOT_SCALE).max(Vector2.ONE))
	snapshot_viewport.transparent_bg = true
	snapshot_viewport.msaa_3d = Viewport.MSAA_DISABLED
	snapshot_viewport.world_3d = view.world_3d
	snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(snapshot_viewport)

	var snapshot_camera := Camera3D.new()
	snapshot_camera.cull_mask = SNAPSHOT_LAYER
	snapshot_camera.keep_aspect = camera.keep_aspect
	snapshot_camera.projection = camera.projection
	snapshot_camera.fov = camera.fov
	snapshot_camera.near = camera.near
	snapshot_camera.far = camera.far
	snapshot_camera.environment = _transparent_environment()
	snapshot_viewport.add_child(snapshot_camera)
	snapshot_camera.global_transform = camera.global_transform
	snapshot_camera.make_current()

	var meshes: Array = []
	for node in enemy.find_children("*", "GeometryInstance3D", true, false):
		var mesh := node as GeometryInstance3D
		if mesh.is_visible_in_tree():
			meshes.append([mesh, mesh.layers])
			mesh.layers |= SNAPSHOT_LAYER

	# Where the enemy was on screen, and which way it is about to move (the smear trails behind that)
	var origin_px := camera.unproject_position(center)
	var scan_dir := -(camera.unproject_position(center + motion_dir) - origin_px)
	scan_dir = scan_dir.normalized() if scan_dir.length() > 0.5 else Vector2.RIGHT
	var distance := camera.global_position.distance_to(center)
	half_extent = maxf(ENEMY_RADIUS / (2.0 * distance * tan(deg_to_rad(camera.fov * 0.5))), 0.01)
	var source_uv := origin_px / full_size

	# Size the streak to the distance the enemy actually covers (it eases out, so about 3/4 of full speed)
	var speed = enemy.get("dodge_speed")
	var duration = enemy.get("dodge_duration")
	dodge_time = duration if duration != null else dodge_time
	var travel: float = (speed if speed != null else 9.0) * dodge_time * 0.75
	var travel_px := camera.unproject_position(center + motion_dir * travel) - origin_px
	stretch_max = clampf(travel_px.length() / full_size.y / (2.0 * half_extent), 0.5, 4.0)

	material = ShaderMaterial.new()
	material.shader = SMEAR_SHADER
	material.render_priority = 100
	material.set_shader_parameter("src_tex", snapshot_viewport.get_texture())
	material.set_shader_parameter("src_centroid", source_uv)
	material.set_shader_parameter("centroid", source_uv)
	material.set_shader_parameter("scan_dir", scan_dir)
	material.set_shader_parameter("half_extent", half_extent)
	material.set_shader_parameter("row_count", ROWS_ACROSS)
	material.set_shader_parameter("frame_aspect", full_size.x / full_size.y)
	material.set_shader_parameter("anchor", -half_extent)  # the leading edge (the enemy's front) stays put, the rest stretches back to where it started

	quad = MeshInstance3D.new()
	var quad_mesh := QuadMesh.new()
	var quad_height := 2.0 * QUAD_DISTANCE * tan(deg_to_rad(camera.fov * 0.5))
	quad_mesh.size = Vector2(quad_height * full_size.x / full_size.y, quad_height)
	quad.mesh = quad_mesh
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.visible = false
	camera.add_child(quad)
	quad.position = Vector3(0.0, 0.0, -QUAD_DISTANCE)

	# The snapshot is drawn at the end of this frame; put the layers back straight after
	await RenderingServer.frame_post_draw
	for entry in meshes:
		if is_instance_valid(entry[0]):
			entry[0].layers = entry[1]
	if is_instance_valid(snapshot_viewport):
		snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED  # keep the snapshot as it is
	started = true
	snapshot_ready.emit()


# The player's environment minus the sky, fog and post effects, so only the enemy lands in the snapshot
func _transparent_environment() -> Environment:
	var base: Environment = camera.environment
	if base == null:
		base = camera.get_world_3d().environment
	var env: Environment = base.duplicate() if base else Environment.new()
	if env.ambient_light_source == Environment.AMBIENT_SOURCE_BG:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if env.reflected_light_source == Environment.REFLECTION_SOURCE_BG:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.glow_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	return env


func _process(delta: float) -> void:
	if not started:
		return
	if not is_instance_valid(camera):
		queue_free()
		return
	elapsed += delta
	var progress := clampf(elapsed / DURATION, 0.0, 1.0)
	if progress >= 1.0:
		queue_free()
		return

	# The head of the smear rides on the enemy, so it moves the same way the enemy does
	if is_instance_valid(follow_enemy):
		head_world = follow_enemy.global_position + Vector3.UP * ENEMY_CENTER_HEIGHT
	quad.visible = not camera.is_position_behind(head_world)
	material.set_shader_parameter("centroid", camera.unproject_position(head_world) / viewport_size)

	var travel_progress := clampf(elapsed / dodge_time, 0.0, 1.0)
	var eased := 1.0 - (1.0 - travel_progress) * (1.0 - travel_progress)
	material.set_shader_parameter("density", lerpf(1.0, 0.55, progress))
	material.set_shader_parameter("stretch", stretch_max * eased)
	material.set_shader_parameter("stagger", half_extent * 0.8 * progress)
	material.set_shader_parameter("line_width", 0.65)
	material.set_shader_parameter("concentration", 0.35)
	material.set_shader_parameter("alpha_gain", 0.85 * pow(1.0 - progress, 1.5))
	material.set_shader_parameter("step_seed", floorf(elapsed * 24.0))  # rows re-roll in steps, not every frame


func _exit_tree() -> void:
	active_count = maxi(active_count - 1, 0)
	if is_instance_valid(quad):
		quad.queue_free()
