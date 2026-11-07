extends Node3D

# Offhand shield. Parry (right click) reflects enemy projectiles back at enemies; throw (F) sends the shield
# out to bounce between enemies and return. Attached to the player's camera, built entirely in code.

const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")
const BloodParticles = preload("res://scripts/weapons/blood_particles.gd")
const ShieldModel = preload("res://scripts/player/shield_model.gd")
const ShieldTrail = preload("res://scripts/player/shield_trail.gd")
const CLANG_SOUND := "res://assets/audio/sfx/impacts/bullet_hit_metal.mp3"
const PARRY_SOUND: AudioStream = preload("res://assets/audio/sfx/impacts/metal_axe_hit.mp3")
const BLOCK_SOUND: AudioStream = preload("res://assets/audio/sfx/player/shield_block.mp3")   # an attack hitting the raised shield
const BLOCK_SOUND_GAP_MSEC := 100   # one attack can report its block twice (a lunge's shove, then its hit)
const THROW_SOUND := "assets/audio/sfx/player/simple_whoosh.mp3"

enum State { READY, PARRY, RECOVER, THROWN, BLOCK }
enum Phase { OUT, BOUNCE, RETURN, GRAPPLE }

# --- Parry ---
@export var parry_window := 0.3
@export var parry_cooldown := 0.7          # after a missed parry
@export var parry_success_cooldown := 0.05 # after a successful parry
@export var parry_input_buffer := 0.2      # a press during that recovery is kept this long and fires once it's ready
@export var block_release_cooldown := 0.15 # after letting go of a block
@export var parry_range := 4.0
@export var melee_parry_range := 3.2       # how close a glowing punch has to be to be parried
# A melee parry is about timing: it only counts if the blow's parry window (which each enemy opens just before it
# connects) is open within this long of the press. Projectiles keep the whole parry_window.
@export var melee_parry_early := 0.15

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

const HELD_SCALE := 1.15
const BLOCK_SCALE := 1.0
const REFLECT_SHOOTER_RANGE := 40.0                 # beyond this the original shooter is "too far" and the nearest enemy is used
const PARRY_SCALE := 1.0
const HELD_POS := Vector3(-0.7, -0.42, -0.62)
const HELD_ROT := Vector3(10.0, 42.0, -8.0)
const PARRY_POS := Vector3(-0.04, -0.5, -0.66)    # parry and block: bottom center, low enough to keep the view clear
const PARRY_ROT := Vector3(4.0, 0.0, 0.0)
# While the shield is up the whole weapon holder tucks down and out to the right, so the gun makes room for it
const GUN_TUCK_POS := Vector3(0.03, -0.028, 0.0)    # the guns sit ~6 cm from the camera, so centimetres go a long way (and never pull it closer: the near plane clips it)
const GUN_TUCK_ROT := Vector3(0.0, 0.0, -10.0)
const GUN_TUCK_SPEED := 16.0
const RECOVER_POS := Vector3(-0.7, -0.52, -0.58)
const HAND_OFFSET := Vector3(-0.55, -0.35, -0.6)
const HAND_STIFFNESS := 700.0
const HAND_DAMPING := 26.0
const PARRY_SWING := 9.0                           # how hard the shield is flung toward the parry pose on a press
const PARRY_SWING_KICK := Vector3(0.0, -0.6, -1.5) # plus a dip and a punch forward, so it reads as a strike
const PARRY_STRIKE_HOLD := 0.16                    # the strike pose is held at least this long, even if a parry lands at once
const PARRY_SUCCESS_HOLD := 0.2                    # and this long after a parry lands, so the hit reads before it goes back
const PARRY_RECOIL := 3.2                          # shove back into the player on a successful parry

const WORLD_MASK := 2       # Environment
const HURTBOX_MASK := 8     # Enemy hurtboxes (shield hitboxes are on this layer too)
const PARRY_COLOR := Color(0.4, 1.4, 2.4)
const PARRY_YELLOW := Color(2.6, 1.9, 0.35)
const GRAPPLE_COLOR := Color(0.4, 2.4, 0.9)
const GRAPPLE_MASK := 64    # PhysicsLayers.GRAPPLE
const ROPE_THICKNESS := 0.05

# Glow colors for the shield states (rim and gem are HDR so they bloom)
const RIM_BASE := Color(2.6, 1.9, 0.3)
const GEM_BASE := Color(0.4, 2.0, 2.6)
const RIM_PARRY := Color(4.2, 3.8, 1.8)         # hot white-yellow, brighter than the resting yellow rim
const GEM_PARRY := Color(3.6, 3.4, 2.0)
const RIM_GRAPPLE := Color(0.5, 3.0, 1.1)       # green, like the grapple points
const GEM_GRAPPLE := Color(0.6, 3.0, 1.2)
const FLASH_COLOR := Color(2.6, 3.4, 3.8)       # cold white flash when the shield is caught or ready again
const RECOVER_DIM := 0.3                        # rim and gem brightness while the shield recovers
const BODY_DIM := 0.55
const FLASH_DECAY := 4.0

static var _glow_texture: GradientTexture2D
static var _clang_stream: AudioStream

var camera: Camera3D
var hand: Node3D
var state := State.READY
var state_timer := 0.0
var parry_succeeded := false
var buffered_parry_until := 0.0            # real seconds (ticks): a press made while recovering from a successful parry
var hand_scale_kick := 0.0
var hand_velocity := Vector3.ZERO
var parry_pressed_msec := 0   # real time of the last parry press (melee parries must land soon after it)
var strike_hold := 0.0   # time left in the parry strike pose (keeps it there after an instant parry)
var gun_tuck := 0.0   # 0 = gun where it belongs, 1 = tucked out of the raised shield's way

# --- Parry impact feel ---
const FlashShader: Shader = preload("res://shaders/player/damage_flash.gdshader")
const HIT_STOP_TIME := 0.06          # real seconds the game is frozen on a successful parry
const HIT_STOP_SCALE := 0.04
const FOV_PUNCH := 7.0               # degrees the FOV snaps out by
const FOV_PUNCH_TIME := 0.22
const RING_TIME := 0.3
const CATCH_RING_COLOR := Color(0.45, 1.5, 1.7)
const PARRY_SPARK_COUNT := 56
const PARRY_EMBER_COUNT := 10
const PARRY_FLASH_COLOR := Color(2.4, 1.8, 0.5)
const CATCH_RING_GROWTH := 1.3     # the catch ring rolls out from the rim to this many times its size
const EDGE_FLASH_TIME := 0.35
const EDGE_FLASH_INTENSITY := 0.85
const PARRY_KICK_PITCH := 0.07

static var _ring_texture: GradientTexture2D

var base_fov := 90.0
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
var flash := 0.0
var previous_state := State.READY


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
			var buffered := Time.get_ticks_msec() / 1000.0 < buffered_parry_until
			if Input.is_action_just_pressed("parry") or buffered:
				buffered_parry_until = 0.0
				_start_parry()
			elif Input.is_action_just_pressed("throw_shield"):
				_start_throw()
		State.PARRY:
			_check_parry()
			state_timer -= delta
			if state == State.PARRY and state_timer <= 0.0:
				# Still holding right click once the parry window closes: keep the shield up as a block
				if Input.is_action_pressed("parry"):
					_set_state(State.BLOCK)
				else:
					_set_state(State.RECOVER, parry_cooldown)
		State.BLOCK:
			if not Input.is_action_pressed("parry"):
				_set_state(State.RECOVER, block_release_cooldown)
		State.RECOVER:
			# Straight after a successful parry the next press isn't lost: it goes off as soon as the shield is ready
			if parry_succeeded and Input.is_action_just_pressed("parry"):
				buffered_parry_until = Time.get_ticks_msec() / 1000.0 + parry_input_buffer
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(State.READY)
		State.THROWN:
			_update_thrown(delta)

	# The hand moves in real time: during a parry's hit-stop the world freezes but the shield still snaps into its strike
	_animate_hand(delta / maxf(Engine.time_scale, 0.001))
	_update_glow(delta)


func _set_state(new_state: State, timer := 0.0) -> void:
	state = new_state
	state_timer = timer
	# While the shield is up (parry window or block) enemy projectiles that reach the player are absorbed
	var player = GlobalVariables.player
	if player and is_instance_valid(player):
		player.shield_blocking = new_state == State.PARRY or new_state == State.BLOCK


# ---------------------------
# Glow states
# ---------------------------
# Rim and gem show what the shield can do: bright yellow while the parry window is open (dimming as it runs
# out), dim while recovering with a flash when it is ready again, a flash when caught, and green while grappling.
func _update_glow(delta: float) -> void:
	flash = maxf(flash - delta * FLASH_DECAY, 0.0)
	if state == State.READY and previous_state == State.RECOVER:
		flash = maxf(flash, 0.8)
	previous_state = state

	var rim := RIM_BASE
	var gem := GEM_BASE
	var body := 1.0
	match state:
		State.PARRY:
			var window_left := clampf(state_timer / maxf(parry_window, 0.01), 0.0, 1.0)
			var strength := 0.3 + 0.7 * window_left
			rim = RIM_BASE.lerp(RIM_PARRY, strength)
			gem = GEM_BASE.lerp(GEM_PARRY, strength)
		State.BLOCK:
			rim = RIM_BASE.lerp(RIM_PARRY, 0.45)
			gem = GEM_BASE.lerp(GEM_PARRY, 0.45)
		State.RECOVER:
			rim = _scaled(RIM_BASE, RECOVER_DIM)
			gem = _scaled(GEM_BASE, RECOVER_DIM)
			body = BODY_DIM
	if parry_succeeded and strike_hold > 0.0 and state != State.PARRY and state != State.BLOCK:
		# A parry that landed stays lit while the shield holds its strike
		rim = RIM_PARRY
		gem = GEM_PARRY
		body = 1.0
	_apply_glow(hand, rim.lerp(FLASH_COLOR, flash), gem.lerp(FLASH_COLOR, flash), body)

	if is_instance_valid(thrown_spinner):
		if phase == Phase.GRAPPLE:
			_apply_glow(thrown_spinner, RIM_GRAPPLE, GEM_GRAPPLE, 1.0)
		else:
			_apply_glow(thrown_spinner, RIM_BASE, GEM_BASE, 1.0)


func _scaled(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, 1.0)


func _apply_glow(model: Node, rim: Color, gem: Color, body: float) -> void:
	if model == null or not model.has_meta("mats"):
		return
	var mats: Dictionary = model.get_meta("mats")
	(mats["rim"] as StandardMaterial3D).albedo_color = rim
	(mats["gem"] as StandardMaterial3D).albedo_color = gem
	(mats["body"] as StandardMaterial3D).albedo_color = Color(body, body, body, 1.0)


# ---------------------------
# Hand animation
# ---------------------------
func _animate_hand(delta: float) -> void:
	hand.visible = state != State.THROWN

	var target_pos := HELD_POS
	var target_rot := HELD_ROT
	var target_scale := HELD_SCALE
	strike_hold = maxf(strike_hold - delta, 0.0)
	match state:
		State.READY:
			target_pos += Vector3(0.0, sin(Time.get_ticks_msec() * 0.002) * 0.006, 0.0)
		State.PARRY:
			target_pos = PARRY_POS
			target_rot = PARRY_ROT
			target_scale = PARRY_SCALE
		State.BLOCK:
			target_pos = PARRY_POS + Vector3(0.0, sin(Time.get_ticks_msec() * 0.012) * 0.004, 0.0)
			target_rot = PARRY_ROT
			target_scale = BLOCK_SCALE
		State.RECOVER:
			target_pos = RECOVER_POS
	if strike_hold > 0.0 and (state == State.READY or state == State.RECOVER):
		# A parry that landed straight away still finishes its strike before the shield goes back
		target_pos = PARRY_POS
		target_rot = PARRY_ROT
		target_scale = PARRY_SCALE

	hand_scale_kick = lerpf(hand_scale_kick, 0.0, 1.0 - exp(-delta * 14.0))
	var blend := 1.0 - exp(-delta * 20.0)
	# Spring (slightly underdamped) so the shield overshoots when it slams into the parry pose
	var step := minf(delta, 0.03)
	hand_velocity += ((target_pos - hand.position) * HAND_STIFFNESS - hand_velocity * HAND_DAMPING) * step
	hand.position += hand_velocity * step
	hand.rotation_degrees = hand.rotation_degrees.lerp(target_rot, blend)
	hand.scale = hand.scale.lerp(Vector3.ONE * (target_scale + hand_scale_kick * 0.5), blend)
	_tuck_gun(delta)


# Moves the gun out of the shield's way while it is up in the middle of the screen, and back after
func _tuck_gun(delta: float) -> void:
	var player = GlobalVariables.player
	if not (player and is_instance_valid(player)) or player.get("weapon_holder") == null:
		return
	var up := state == State.PARRY or state == State.BLOCK or strike_hold > 0.0
	gun_tuck = lerpf(gun_tuck, 1.0 if up else 0.0, 1.0 - exp(-delta * GUN_TUCK_SPEED))
	var t := ease(gun_tuck, -1.8)   # in-out, so it starts and settles softly
	var holder: Node3D = player.weapon_holder
	holder.position = GUN_TUCK_POS * t
	holder.rotation_degrees = GUN_TUCK_ROT * t


# ---------------------------
# Parry
# ---------------------------
func _start_parry() -> void:
	parry_succeeded = false
	parry_pressed_msec = Time.get_ticks_msec()
	_set_state(State.PARRY, parry_window)
	strike_hold = PARRY_STRIKE_HOLD
	# Swing over from wherever the shield is (no teleport), dipping low and punching forward into the parry pose
	hand_velocity = (PARRY_POS - hand.position) * PARRY_SWING + PARRY_SWING_KICK
	hand.rotation_degrees.z = -14.0
	hand_scale_kick = 0.2
	Audio.play(THROW_SOUND)


func _check_parry() -> void:
	var forward := -camera.global_basis.z
	var reflected_any := false
	for projectile in get_tree().get_nodes_in_group("EnemyProjectile"):
		if not is_instance_valid(projectile) or projectile.reflected:
			continue
		var to_projectile: Vector3 = projectile.global_position - camera.global_position
		if to_projectile.length() > parry_range or to_projectile.normalized().dot(forward) < 0.0:
			continue
		_reflect(projectile)
		reflected_any = true
	if reflected_any:
		return

	# Melee: a yellow blow can be parried once the enemy is close enough, but only if the press was well timed: it has
	# to come at most melee_parry_early before the blow's own (short) parry window, so pressing early whiffs
	if Time.get_ticks_msec() - parry_pressed_msec > melee_parry_early * 1000.0:
		return
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy) or enemy.get("parryable") != true:
			continue
		# A big enemy can say where the part to parry is (the hand boss's jabbing fingertip)
		var parry_at: Vector3 = enemy.parry_point() if enemy.has_method("parry_point") else enemy.global_position + Vector3.UP * 1.0
		var to_enemy: Vector3 = parry_at - camera.global_position
		if to_enemy.length() > melee_parry_range or to_enemy.normalized().dot(forward) < 0.2:
			continue
		_parry_melee(enemy)
		return


var last_block_msec := -BLOCK_SOUND_GAP_MSEC


# An attack hit the raised shield: a projectile (absorbed) or a melee blow (taken at reduced damage)
func on_block_hit(point: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - last_block_msec < BLOCK_SOUND_GAP_MSEC:
		return
	last_block_msec = now
	_clang(point, 1.0, BLOCK_SOUND)
	_pop(point, PARRY_YELLOW, 0.9)
	ImpactParticles.spawn(get_tree(), point, (camera.global_position - point).normalized(), 1.0)
	hand_velocity += Vector3(0.0, 0.0, 1.6)
	hand_scale_kick = 0.2
	flash = maxf(flash, 0.7)
	var owner_player = GlobalVariables.player
	if owner_player and is_instance_valid(owner_player):
		owner_player.apply_camera_kick(0.03, randf_range(-0.01, 0.01))


func _reflect(projectile: Node3D) -> void:
	# Prefer the enemy that fired it; fall back to the nearest one if it is dead or out of range
	var enemy: Node3D = null
	var shooter = projectile.get("shooter")
	if _is_valid_enemy(shooter):
		var chest: Vector3 = shooter.global_position + Vector3.UP * 1.2
		if projectile.get("always_return_to_shooter") == true or projectile.global_position.distance_to(chest) <= REFLECT_SHOOTER_RANGE:
			enemy = shooter
	if enemy == null:
		enemy = _nearest_enemy(projectile.global_position, 80.0, false)
	var direction := -camera.global_basis.z
	if enemy:
		direction = (enemy.global_position + Vector3.UP * 1.2) - projectile.global_position
	projectile.reflect(enemy, direction)
	_parry_feedback(projectile.global_position)


# A melee attack from `attacker` landed while the shield was held up: the same feedback as a blocked shot, at the
# shield's side of the blow. Does nothing if the shield isn't up.
func on_melee_blocked(attacker: Node3D) -> void:
	var owner_player = GlobalVariables.player
	if owner_player == null or not is_instance_valid(owner_player) or owner_player.get("shield_blocking") != true:
		return
	var chest := attacker.global_position + Vector3.UP * 1.2
	on_block_hit(camera.global_position.lerp(chest, 0.35))


# A glowing punch was caught: the enemy's attack is cancelled and it is stunned and knocked back
func _parry_melee(enemy: Node3D) -> void:
	var point: Vector3 = enemy.global_position + Vector3.UP * 1.3
	point = camera.global_position.lerp(point, 0.7)
	if enemy.has_method("on_parried"):
		enemy.on_parried()
	if enemy.has_method("hit_flash"):
		enemy.hit_flash(point, 3.0, 1.9)
	_parry_feedback(point)


# Shared by every successful parry: clang, sparks, shove-back, camera kick, hit-stop and the rest of the juice
func _parry_feedback(point: Vector3) -> void:
	_clang(point, 1.0, PARRY_SOUND)
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
	strike_hold = maxf(strike_hold, PARRY_SUCCESS_HOLD)
	_set_state(State.RECOVER, parry_success_cooldown)


# ---------------------------
# Throw
# ---------------------------
func _exit_tree() -> void:
	_remove_rope()
	# Never leave the game in slow motion if the player is freed mid hit-stop (death, scene reload)
	Engine.time_scale = 1.0


func _parry_impact_effects(point: Vector3) -> void:
	GameManager.hit_stop(HIT_STOP_TIME, HIT_STOP_SCALE)
	_fov_punch()
	_edge_flash()
	_parry_ring()


# A parry throws sparks off the shield like metal striking metal: hot streaks spraying from the whole rim out and
# forward, a few heavier slow embers, and a quick bright flash on the face. Everything is parented to the hand so it
# starts on the shield, while the sparks themselves fly free in the world.
func _parry_ring() -> void:
	var centre := _hand_disc_centre()
	var radius := _hand_disc_radius()
	_spark_burst(centre, radius, PARRY_SPARK_COUNT, 1.2, 4.0, 0.012, 0.35)
	_spark_burst(centre, radius * 0.6, PARRY_EMBER_COUNT, 0.5, 1.8, 0.02, 0.6)
	_plane_effect(_glow_tex(), PARRY_FLASH_COLOR, radius * 1.4, radius * 2.4, 0.12)


func _spark_burst(centre: Vector3, radius: float, count: int, speed_min: float, speed_max: float, size: float, life: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.use_particle_trails = true
	material.albedo_color = Color(3.0, 2.3, 0.8)
	var mesh := RibbonTrailMesh.new()
	mesh.shape = RibbonTrailMesh.SHAPE_CROSS
	mesh.size = size
	mesh.sections = 4
	mesh.section_length = 0.03
	mesh.section_segments = 1
	mesh.material = material

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.97, 0.75, 1.0),
		Color(1.0, 0.72, 0.2, 0.95),
		Color(1.0, 0.4, 0.05, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.BACK
	process.emission_ring_radius = radius
	process.emission_ring_inner_radius = radius * 0.5
	process.emission_ring_height = 0.0
	process.direction = Vector3.FORWARD
	process.spread = 55.0
	process.initial_velocity_min = speed_min * 0.4
	process.initial_velocity_max = speed_max * 0.5
	process.radial_velocity_min = speed_min * 0.6
	process.radial_velocity_max = speed_max
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.damping_min = 1.5
	process.damping_max = 4.0
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color_ramp = ramp

	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = count
	sparks.lifetime = life
	# The shield is still swinging into its parry pose when the parry lands, so sparks left in world space would
	# stay behind at the resting (right-hand) spot. In local space they ride the hand and burst from the shield itself.
	sparks.local_coords = true
	sparks.trail_enabled = true
	sparks.trail_lifetime = 0.08
	sparks.process_material = process
	sparks.draw_pass_1 = mesh
	sparks.position = centre
	sparks.visibility_aabb = AABB(Vector3(-4, -4, -6), Vector3(8, 8, 8))
	hand.add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(life + 0.5, true, false, true).timeout.connect(sparks.queue_free)


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


# Thin bright ring used by the catch
func _ring_tex() -> GradientTexture2D:
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
	return _ring_texture


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

	var trail := ShieldTrail.new()
	trail.target = thrown
	thrown.add_child(trail)

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
	elif _hit_breakable(hit["collider"], point):
		pass   # it broke: the shield carries on through
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
	var point := hand.global_position     # the burst happens at the hand, where the shield lands
	_catch_burst()
	ImpactParticles.spawn(get_tree(), point, (camera.global_position - point).normalized(), 0.9)
	_clang(thrown.global_position, 1.2)
	thrown.queue_free()
	thrown = null
	bounce_target = null
	visited_ids.clear()

	# The shield slaps back into the hand: the rim flashes, it bumps and the camera gives a little
	flash = 1.0
	hand_scale_kick = 0.5
	hand_velocity += Vector3(0.0, 0.0, 2.5)
	var owner_player = GlobalVariables.player
	if owner_player and is_instance_valid(owner_player):
		owner_player.apply_camera_kick(0.02, 0.0)
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


# Barrels and windows (the "Blastable" group) take the throw like an enemy would, minus the blood. Returns whether the
# shield broke it and so flies on; a barrel that survives (or is only lit, like an explosive one) stops it as a wall does.
func _hit_breakable(collider: Object, point: Vector3) -> bool:
	if not (collider is Node and collider.is_in_group("Blastable") and collider.has_method("damage")):
		return false
	_clang(point, 0.9)
	_pop(point, PARRY_COLOR, 1.0)
	collider.damage(throw_damage)
	if not is_instance_valid(collider) or collider.get("broken") == true:
		return true
	phase = Phase.RETURN
	ImpactParticles.spawn(get_tree(), point, -fly_dir, 0.8)
	return true


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
		BloodParticles.spawn(get_tree(), point, direction, 0.8, BloodParticles.thickness_for(enemy))

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


# face_forward: held in the hand, the front (dome) facing away towards enemies and the back towards the player.
# Otherwise (thrown) it lies flat with the dome up.
func _make_disc(face_forward: bool) -> Node3D:
	var root := ShieldModel.build()

	if face_forward:
		root.rotation_degrees.x = -90.0
		var holder := Node3D.new()
		holder.add_child(root)
		holder.set_meta("mats", root.get_meta("mats"))
		return holder
	return root


func _clang(position_in_world: Vector3, pitch: float, stream: AudioStream = null) -> void:
	if _clang_stream == null:
		_clang_stream = load(CLANG_SOUND)
	var player := AudioStreamPlayer3D.new()
	player.stream = stream if stream else _clang_stream
	player.bus = "SFX"
	player.volume_db = -2.0
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.max_distance = 40.0
	player.unit_size = 6.0
	player.attenuation_filter_db = 0.0
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.global_position = position_in_world
	player.play()


# The catch flash: a glow over the face and a ring rolling out from the rim, both lying in the shield's own plane and
# riding on the hand, so they match the tilted disc on screen instead of a flat circle floating over it.
func _catch_burst() -> void:
	var radius := _hand_disc_radius()
	# The ring texture's bright band sits 0.41 of the quad's width from its centre
	var rim_quad := radius / 0.41
	_plane_effect(_glow_tex(), FLASH_COLOR * 0.22, radius * 1.6, radius * 2.0, 0.16)
	_plane_effect(_ring_tex(), CATCH_RING_COLOR, rim_quad, rim_quad * CATCH_RING_GROWTH, RING_TIME)


func _plane_effect(texture: Texture2D, color: Color, from_size: float, to_size: float, time: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_texture = texture
	material.albedo_color = color
	var effect := MeshInstance3D.new()
	effect.mesh = QuadMesh.new()   # faces +Z: the hand's disc lies in its local XY plane
	effect.material_override = material
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.position = _hand_disc_centre()
	effect.scale = Vector3.ONE * from_size
	hand.add_child(effect)
	var tween := effect.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tween.tween_property(effect, "scale", Vector3.ONE * to_size, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(0.0, 0.0, 0.0), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(effect.queue_free)


# The held disc's bounds in the hand's own space (unscaled), measured once from its meshes
var _disc_bounds := AABB()


func _hand_disc_bounds() -> AABB:
	if _disc_bounds.size != Vector3.ZERO:
		return _disc_bounds
	var to_hand := hand.global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for mesh_instance in hand.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (to_hand * (mesh_instance as MeshInstance3D).global_transform) * (mesh_instance as MeshInstance3D).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	_disc_bounds = bounds
	return bounds


func _hand_disc_radius() -> float:
	var size := _hand_disc_bounds().size
	return maxf(size.x, size.y) * 0.5


# Centre of the disc's face on the side the player sees (the back, +Z), so the burst sits on the shield, not inside it
func _hand_disc_centre() -> Vector3:
	var bounds := _hand_disc_bounds()
	var centre := bounds.get_center()
	centre.z = bounds.end.z
	return centre


func _pop(position_in_world: Vector3, color: Color, size: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.albedo_texture = _glow_tex()
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


# Soft round glow shared by every pop
func _glow_tex() -> GradientTexture2D:
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
	return _glow_texture
