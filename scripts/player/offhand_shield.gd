extends Node3D

# Offhand shield. Parry (F) reflects enemy projectiles back at enemies; throw (G) sends the shield
# out to bounce between enemies and return. Attached to the player's camera, built entirely in code.

const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")
const BloodParticles = preload("res://scripts/weapons/blood_particles.gd")
const CLANG_SOUND := "res://assets/sounds/bullet_hit_metal.mp3"
const THROW_SOUND := "assets/sounds/simple_whoosh.mp3"

enum State { READY, PARRY, RECOVER, THROWN }
enum Phase { OUT, BOUNCE, RETURN, GRAPPLE }

# --- Parry ---
@export var parry_window := 0.3
@export var parry_cooldown := 0.7          # after a missed parry
@export var parry_success_cooldown := 0.15 # after reflecting something
@export var parry_range := 4.0

# --- Throw ---
@export var throw_damage := 45.0
@export var max_bounces := 4
@export var throw_speed := 38.0
@export var return_speed := 48.0
@export var bounce_radius := 11.0
@export var throw_range := 60.0
@export var catch_distance := 1.3
@export var throw_cooldown := 0.4
@export var max_flight_time := 6.0
@export var grapple_aim_assist_degrees := 3.0   # a grapple point this close to the crosshair is aimed at for you

const HELD_SCALE := 0.45
const PARRY_SCALE := 0.85
const HELD_POS := Vector3(-0.38, -0.3, -0.6)
const HELD_ROT := Vector3(0.0, 22.0, 0.0)
const PARRY_POS := Vector3(-0.02, -0.08, -0.75)
const PARRY_ROT := Vector3(0.0, 0.0, 0.0)
const RECOVER_POS := Vector3(-0.38, -0.38, -0.55)
const HAND_OFFSET := Vector3(-0.3, -0.25, -0.6)
const HAND_STIFFNESS := 700.0
const HAND_DAMPING := 26.0
const PARRY_PULLBACK := Vector3(0.0, -0.05, 0.3)   # where the shield starts before slamming forward
const PARRY_SLAM_SPEED := 5.0
const PARRY_RECOIL := 3.2                          # shove back into the player on a successful parry

const WORLD_MASK := 2       # Environment
const HURTBOX_MASK := 8     # Enemy hurtboxes (shield hitboxes are on this layer too)
const PARRY_COLOR := Color(0.4, 1.4, 2.4)
const PARRY_YELLOW := Color(2.6, 1.9, 0.35)
const GRAPPLE_COLOR := Color(0.4, 2.4, 0.9)
const GRAPPLE_MASK := 64    # PhysicsLayers.GRAPPLE
const ROPE_THICKNESS := 0.05

static var _glow_texture: GradientTexture2D
static var _clang_stream: AudioStream

var camera: Camera3D
var hand: Node3D
var state := State.READY
var state_timer := 0.0
var parry_succeeded := false
var hand_scale_kick := 0.0
var hand_velocity := Vector3.ZERO

# --- Parry impact feel ---
const FlashShader: Shader = preload("res://shaders/damage_flash.gdshader")
const HIT_STOP_TIME := 0.06          # real seconds the game is frozen on a successful parry
const HIT_STOP_SCALE := 0.04
const FOV_PUNCH := 7.0               # degrees the FOV snaps out by
const FOV_PUNCH_TIME := 0.22
const RING_TIME := 0.3
const RING_SIZE := 3.2
const EDGE_FLASH_TIME := 0.35
const EDGE_FLASH_INTENSITY := 0.85
const PARRY_KICK_PITCH := 0.07

static var _ring_texture: GradientTexture2D

var base_fov := 90.0
var hit_stop_active := false
var edge_material: ShaderMaterial
var edge_tween: Tween
var fov_tween: Tween

var thrown: Node3D
var thrown_spinner: Node3D
var phase := Phase.OUT
var fly_dir := Vector3.FORWARD
var traveled := 0.0
var flight_time := 0.0
var bounces := 0
var visited_ids: Array[int] = []
var bounce_target: Node3D
var grapple_point: Node3D
var rope: MeshInstance3D


func _ready() -> void:
	camera = get_parent() as Camera3D
	base_fov = camera.fov
	_setup_edge_flash()
	hand = _make_disc(true)
	hand.position = HELD_POS
	add_child(hand)


func _process(delta: float) -> void:
	match state:
		State.READY:
			if Input.is_action_just_pressed("parry"):
				_start_parry()
			elif Input.is_action_just_pressed("throw_shield"):
				_start_throw()
		State.PARRY:
			_check_parry()
			state_timer -= delta
			if state == State.PARRY and state_timer <= 0.0:
				_set_state(State.RECOVER, parry_cooldown)
		State.RECOVER:
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(State.READY)
		State.THROWN:
			_update_thrown(delta)

	_animate_hand(delta)


func _set_state(new_state: State, timer := 0.0) -> void:
	state = new_state
	state_timer = timer


# ---------------------------
# Hand animation
# ---------------------------
func _animate_hand(delta: float) -> void:
	hand.visible = state != State.THROWN

	var target_pos := HELD_POS
	var target_rot := HELD_ROT
	var target_scale := HELD_SCALE
	match state:
		State.READY:
			target_pos += Vector3(0.0, sin(Time.get_ticks_msec() * 0.002) * 0.006, 0.0)
		State.PARRY:
			target_pos = PARRY_POS
			target_rot = PARRY_ROT
			target_scale = PARRY_SCALE
		State.RECOVER:
			target_pos = RECOVER_POS

	hand_scale_kick = lerpf(hand_scale_kick, 0.0, 1.0 - exp(-delta * 14.0))
	var blend := 1.0 - exp(-delta * 20.0)
	# Spring (slightly underdamped) so the shield overshoots when it slams into the parry pose
	var step := minf(delta, 0.03)
	hand_velocity += ((target_pos - hand.position) * HAND_STIFFNESS - hand_velocity * HAND_DAMPING) * step
	hand.position += hand_velocity * step
	hand.rotation_degrees = hand.rotation_degrees.lerp(target_rot, blend)
	hand.scale = hand.scale.lerp(Vector3.ONE * (target_scale + hand_scale_kick * 0.5), blend)


# ---------------------------
# Parry
# ---------------------------
func _start_parry() -> void:
	parry_succeeded = false
	_set_state(State.PARRY, parry_window)
	hand.position = PARRY_POS + PARRY_PULLBACK
	hand_velocity = Vector3(0.0, 0.0, -PARRY_SLAM_SPEED)
	hand.rotation_degrees.z = -14.0
	hand_scale_kick = 0.2
	Audio.play(THROW_SOUND)


func _check_parry() -> void:
	var forward := -camera.global_basis.z
	for projectile in get_tree().get_nodes_in_group("EnemyProjectile"):
		if not is_instance_valid(projectile) or projectile.reflected:
			continue
		var to_projectile: Vector3 = projectile.global_position - camera.global_position
		if to_projectile.length() > parry_range or to_projectile.normalized().dot(forward) < 0.0:
			continue
		_reflect(projectile)


func _reflect(projectile: Node3D) -> void:
	var enemy := _nearest_enemy(projectile.global_position, 80.0, false)
	var direction := -camera.global_basis.z
	if enemy:
		direction = (enemy.global_position + Vector3.UP * 1.2) - projectile.global_position
	projectile.reflect(enemy, direction)

	var point := projectile.global_position
	_clang(point, 1.5)
	_pop(point, PARRY_YELLOW, 1.4)
	hand_velocity += Vector3(0.0, 0.0, PARRY_RECOIL)
	hand.rotation_degrees.z = 9.0
	ImpactParticles.spawn(get_tree(), point, (camera.global_position - point).normalized(), 1.2)

	var owner_player = GlobalVariables.player
	if owner_player and is_instance_valid(owner_player):
		owner_player.apply_camera_kick(PARRY_KICK_PITCH, randf_range(-0.012, 0.012))

	hand_scale_kick = 0.35
	_parry_impact_effects(point)
	parry_succeeded = true
	_set_state(State.RECOVER, parry_success_cooldown)


# ---------------------------
# Throw
# ---------------------------
func _exit_tree() -> void:
	_remove_rope()
	# Never leave the game in slow motion if the player is freed mid hit-stop (death, scene reload)
	Engine.time_scale = 1.0


func _parry_impact_effects(point: Vector3) -> void:
	_hit_stop()
	_fov_punch()
	_edge_flash()
	_shockwave_ring(point)


func _hit_stop() -> void:
	if hit_stop_active:
		return
	hit_stop_active = true
	Engine.time_scale = HIT_STOP_SCALE
	# Timer ignores time scale, so the freeze lasts HIT_STOP_TIME in real time
	await get_tree().create_timer(HIT_STOP_TIME, true, false, true).timeout
	Engine.time_scale = 1.0
	hit_stop_active = false


func _fov_punch() -> void:
	if fov_tween:
		fov_tween.kill()
	camera.fov = base_fov + FOV_PUNCH
	fov_tween = create_tween().set_ignore_time_scale(true)
	fov_tween.tween_property(camera, "fov", base_fov, FOV_PUNCH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _setup_edge_flash() -> void:
	# Cyan screen-edge flash: the parry counterpart of the red damage flash, under the HUD
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)

	edge_material = ShaderMaterial.new()
	edge_material.shader = FlashShader
	edge_material.set_shader_parameter("flash_color", Color(1.0, 0.85, 0.15, 1.0))
	edge_material.set_shader_parameter("edge_power", 1.6)
	edge_material.set_shader_parameter("inner_ratio", 0.6)
	edge_material.set_shader_parameter("feather", 0.5)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = edge_material
	layer.add_child(rect)


func _edge_flash() -> void:
	if edge_tween:
		edge_tween.kill()
	_set_edge_intensity(EDGE_FLASH_INTENSITY)
	edge_tween = create_tween().set_ignore_time_scale(true)
	edge_tween.tween_method(_set_edge_intensity, EDGE_FLASH_INTENSITY, 0.0, EDGE_FLASH_TIME)


func _set_edge_intensity(value: float) -> void:
	edge_material.set_shader_parameter("intensity", value)


func _shockwave_ring(point: Vector3) -> void:
	if _ring_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.6, 0.82, 0.92, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 0.85, 0.2, 0.45),
			Color(1.0, 0.65, 0.1, 0.0),
		])
		_ring_texture = GradientTexture2D.new()
		_ring_texture.gradient = gradient
		_ring_texture.fill = GradientTexture2D.FILL_RADIAL
		_ring_texture.fill_from = Vector2(0.5, 0.5)
		_ring_texture.fill_to = Vector2(1.0, 0.5)
		_ring_texture.width = 256
		_ring_texture.height = 256

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.albedo_texture = _ring_texture
	material.albedo_color = Color(4.0, 3.4, 1.0)

	var ring := MeshInstance3D.new()
	ring.mesh = QuadMesh.new()
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 0.3
	get_tree().root.add_child(ring)
	ring.global_position = point

	var tween := ring.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tween.tween_property(ring, "scale", Vector3.ONE * RING_SIZE, RING_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(0.0, 0.0, 0.0), RING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


func _start_throw() -> void:
	var start := camera.global_position + camera.global_basis * HAND_OFFSET

	# Aim at whatever is under the crosshair, so the shield flies where you are looking
	var forward := -camera.global_basis.z
	var aim_point := camera.global_position + forward * throw_range
	var aim_hit := _raycast(camera.global_position, aim_point, WORLD_MASK | HURTBOX_MASK | GRAPPLE_MASK)
	if not aim_hit.is_empty():
		aim_point = aim_hit["position"]
	aim_point = _grapple_aim_assist(aim_point)
	fly_dir = (aim_point - start).normalized()

	thrown = Node3D.new()
	thrown_spinner = _make_disc(false)
	thrown.add_child(thrown_spinner)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.8, 1.0)
	light.light_energy = 2.0
	light.omni_range = 3.5
	thrown.add_child(light)
	get_tree().current_scene.add_child(thrown)
	thrown.global_position = start

	phase = Phase.OUT
	traveled = 0.0
	flight_time = 0.0
	bounces = 0
	bounce_target = null
	visited_ids.clear()
	_set_state(State.THROWN)
	Audio.play(THROW_SOUND)


func _update_thrown(delta: float) -> void:
	if not is_instance_valid(thrown):
		_set_state(State.READY)
		return

	flight_time += delta
	thrown_spinner.rotate_y(delta * 22.0)
	if flight_time > max_flight_time and phase != Phase.RETURN and phase != Phase.GRAPPLE:
		phase = Phase.RETURN

	match phase:
		Phase.OUT:
			_update_out(delta)
		Phase.BOUNCE:
			_update_bounce(delta)
		Phase.RETURN:
			_update_return(delta)
		Phase.GRAPPLE:
			_update_grapple()


func _update_out(delta: float) -> void:
	var from := thrown.global_position
	var step := fly_dir * throw_speed * delta
	var hit := _raycast(from, from + step, WORLD_MASK | HURTBOX_MASK | GRAPPLE_MASK)

	if hit.is_empty():
		thrown.global_position = from + step
		traveled += step.length()
		if traveled >= throw_range:
			phase = Phase.RETURN
		return

	var point: Vector3 = hit["position"]
	thrown.global_position = point
	if hit["collider"] is Node and (hit["collider"] as Node).is_in_group("GrapplePoint"):
		_attach_to_grapple(hit["collider"] as Node3D)
		return
	var enemy := _enemy_from_collider(hit["collider"])
	if enemy:
		_hit_enemy(enemy, point)
	else:
		_clang(point, 0.8)
		ImpactParticles.spawn(get_tree(), point, hit["normal"], 0.8)
		phase = Phase.RETURN


func _update_bounce(delta: float) -> void:
	if not _is_valid_enemy(bounce_target):
		bounce_target = _nearest_enemy(thrown.global_position, bounce_radius, true)
		if bounce_target == null:
			phase = Phase.RETURN
			return

	var destination := bounce_target.global_position + Vector3.UP * 1.2
	var to_target := destination - thrown.global_position
	var step_length := throw_speed * delta
	fly_dir = to_target.normalized()

	if to_target.length() <= step_length + 0.5:
		thrown.global_position = destination
		_hit_enemy(bounce_target, destination)
		return

	var from := thrown.global_position
	var step := fly_dir * step_length
	if not _raycast(from, from + step, WORLD_MASK).is_empty():
		phase = Phase.RETURN
		return
	thrown.global_position = from + step


func _update_return(delta: float) -> void:
	var hand_point := camera.global_position + camera.global_basis * HAND_OFFSET
	var to_hand := hand_point - thrown.global_position
	if to_hand.length() <= catch_distance:
		_catch()
		return
	thrown.global_position += to_hand.normalized() * minf(return_speed * delta, to_hand.length())


func _catch() -> void:
	_remove_rope()
	_pop(thrown.global_position, PARRY_COLOR, 0.8)
	_clang(thrown.global_position, 1.2)
	thrown.queue_free()
	thrown = null
	bounce_target = null
	visited_ids.clear()
	hand_scale_kick = 0.3
	_set_state(State.RECOVER, throw_cooldown)


# ---------------------------
# Grapple
# ---------------------------
# Among the grapple points near the crosshair, picks the closest one to the aim line (if nothing blocks it
# and it is not behind whatever the throw would hit) and returns it; otherwise returns the original aim point.
func _grapple_aim_assist(aim_point: Vector3) -> Vector3:
	if grapple_aim_assist_degrees <= 0.0:
		return aim_point
	var forward := -camera.global_basis.z
	var max_distance := camera.global_position.distance_to(aim_point) + 0.5
	var best_angle := deg_to_rad(grapple_aim_assist_degrees)
	var best_point := aim_point
	for candidate in get_tree().get_nodes_in_group("GrapplePoint"):
		var point_node := candidate as Node3D
		if point_node == null:
			continue
		var to_point := point_node.global_position - camera.global_position
		var distance := to_point.length()
		if distance > throw_range or distance > max_distance:
			continue
		var angle := forward.angle_to(to_point)
		if angle >= best_angle:
			continue
		if not _raycast(camera.global_position, point_node.global_position, WORLD_MASK).is_empty():
			continue
		best_angle = angle
		best_point = point_node.global_position
	return best_point


# The shield hit a grapple point: it sticks there and the player is pulled over to it
func _attach_to_grapple(point_node: Node3D) -> void:
	var player := get_tree().get_first_node_in_group("Player")
	if player == null or not player.has_method("start_grapple"):
		phase = Phase.RETURN
		return
	grapple_point = point_node
	thrown.global_position = point_node.global_position
	if point_node.has_method("on_grappled"):
		point_node.on_grappled()
	_pop(point_node.global_position, GRAPPLE_COLOR, 1.3)
	_clang(point_node.global_position, 1.4)
	Audio.play(THROW_SOUND)
	_make_rope()
	player.start_grapple(point_node.global_position)
	phase = Phase.GRAPPLE


func _update_grapple() -> void:
	var player := get_tree().get_first_node_in_group("Player")
	var pulling: bool = player != null and player.get("grappling") == true
	if pulling and Input.is_action_just_pressed("throw_shield"):
		player.end_grapple(false)      # throwing again lets go
		pulling = false
	if not pulling or not is_instance_valid(grapple_point):
		_remove_rope()
		grapple_point = null
		phase = Phase.RETURN
		return
	thrown.global_position = grapple_point.global_position
	_update_rope()


# A glowing green line from the player's hand to the shield while they are being pulled
func _make_rope() -> void:
	_remove_rope()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.4, 2.2, 0.9)
	material.disable_fog = true
	var box := BoxMesh.new()
	box.size = Vector3(ROPE_THICKNESS, ROPE_THICKNESS, 1.0)
	box.material = material
	rope = MeshInstance3D.new()
	rope.mesh = box
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(rope)
	_update_rope()


func _update_rope() -> void:
	if not is_instance_valid(rope) or not is_instance_valid(thrown):
		return
	var from := camera.global_position + camera.global_basis * HAND_OFFSET
	var to := thrown.global_position
	var length := from.distance_to(to)
	if length < 0.05:
		return
	rope.global_position = (from + to) * 0.5
	rope.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	rope.scale = Vector3(1.0, 1.0, length)


func _remove_rope() -> void:
	if is_instance_valid(rope):
		rope.queue_free()
	rope = null


func _hit_enemy(enemy: Node3D, point: Vector3) -> void:
	var shielded := "shield" in enemy and enemy.shield != null and is_instance_valid(enemy.shield)
	var direction := fly_dir

	if enemy.has_method("hit_flash"):
		enemy.hit_flash(point, 1.5)
	if enemy.has_method("damage"):
		enemy.damage(throw_damage)

	_clang(point, 0.9 + 0.12 * bounces)
	_pop(point, PARRY_COLOR, 1.0)
	if shielded:
		ImpactParticles.spawn(get_tree(), point, -direction, 1.0)
	else:
		BloodParticles.spawn(get_tree(), point, direction, 0.8)

	visited_ids.append(enemy.get_instance_id())
	bounces += 1
	if bounces >= max_bounces:
		phase = Phase.RETURN
		return

	bounce_target = _nearest_enemy(thrown.global_position, bounce_radius, true)
	phase = Phase.BOUNCE if bounce_target else Phase.RETURN


# ---------------------------
# Helpers
# ---------------------------
func _raycast(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _enemy_from_collider(collider: Object) -> Node3D:
	if not collider is Node:
		return null
	if collider.is_in_group("Shield"):
		return collider.get_parent().get_parent()
	if collider.is_in_group("Enemy"):
		return collider
	return collider.get("owner_enemy")


func _is_valid_enemy(enemy) -> bool:
	return is_instance_valid(enemy) and enemy is Node3D and not enemy.get("destroyed")


func _nearest_enemy(from_position: Vector3, max_distance: float, need_line_of_sight: bool) -> Node3D:
	var best: Node3D = null
	var best_d2 := max_distance * max_distance
	for candidate in get_tree().get_nodes_in_group("Enemy"):
		if not _is_valid_enemy(candidate) or candidate.get_instance_id() in visited_ids:
			continue
		var enemy: Node3D = candidate
		var chest: Vector3 = enemy.global_position + Vector3.UP * 1.2
		var d2 := from_position.distance_squared_to(chest)
		if d2 >= best_d2:
			continue
		if need_line_of_sight and not _raycast(from_position, chest, WORLD_MASK).is_empty():
			continue
		best = enemy
		best_d2 = d2
	return best


func _make_disc(face_forward: bool) -> Node3D:
	var root := Node3D.new()

	var body_material := StandardMaterial3D.new()
	body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_material.albedo_color = Color(0.3, 1.4, 2.0)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.26
	cylinder.bottom_radius = 0.26
	cylinder.height = 0.035
	cylinder.radial_segments = 32
	cylinder.rings = 1
	cylinder.material = body_material
	var body := MeshInstance3D.new()
	body.mesh = cylinder
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)

	var rim_material := StandardMaterial3D.new()
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.albedo_color = Color(2.4, 0.4, 1.9)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.235
	torus.outer_radius = 0.285
	torus.rings = 32
	torus.ring_segments = 6
	torus.material = rim_material
	var rim := MeshInstance3D.new()
	rim.mesh = torus
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)

	if face_forward:
		root.rotation_degrees.x = 90.0
		var holder := Node3D.new()
		holder.add_child(root)
		return holder
	return root


func _clang(position_in_world: Vector3, pitch: float) -> void:
	if _clang_stream == null:
		_clang_stream = load(CLANG_SOUND)
	var player := AudioStreamPlayer3D.new()
	player.stream = _clang_stream
	player.bus = "SFX"
	player.volume_db = -2.0
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.max_distance = 40.0
	player.unit_size = 6.0
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.global_position = position_in_world
	player.play()


func _pop(position_in_world: Vector3, color: Color, size: float) -> void:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(0.7, 0.9, 1.0, 0.7),
			Color(0.3, 0.6, 1.0, 0.0),
		])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 128
		_glow_texture.height = 128

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.albedo_texture = _glow_texture
	material.albedo_color = color

	var pop := MeshInstance3D.new()
	pop.mesh = QuadMesh.new()
	pop.material_override = material
	pop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pop.scale = Vector3.ONE * 0.2
	get_tree().root.add_child(pop)
	pop.global_position = position_in_world

	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "scale", Vector3.ONE * size, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(0.0, 0.0, 0.0), 0.2)
	tween.chain().tween_callback(pop.queue_free)
