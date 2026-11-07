extends CharacterBody3D

@export_subgroup("Properties")
@export var base_movement_speed = 10
@export var base_slide_speed = 10
@export var jump_strength = 8
@export var max_slide_speed = 12
@export var mouse_sensitivity = 20
@export var dash_speed = 25
@export var dash_duration = 0.2
@export var dash_cooldown = 0.75   # seconds for one spent dash to come back once the player has touched the ground or a wall; each of the DASH_CHARGES recharges on its own
@export var wall_jump_strength = 8
@export var wall_jump_push = 10.0
@export var wall_jump_push_time = 0.2
@export var kick_recovery = 14.0
@export var damage_flash_time = 0.4
@export var heal_flash_time = 0.6
@export var kill_heal_range := 4.0   # killing an enemy this close (metres) sends its health packs flying to you; further away they drop on the floor to pick up
@export var fall_reset_distance := 60.0   # falling this far below the last solid ground counts as falling off the map. Must be more than the level's deepest real drop.
@export var fall_damage := 20
@export var kill_height := -70.0      # falling below this before ever touching the ground restarts the level
@export var grapple_speed := 34.0              # how fast the shield grapple pulls the player
@export var grapple_arrive_distance := 1.8      # stops this close (camera to point) to the grapple point
@export var grapple_max_time := 1.6
@export var grapple_release_carry := 0.55       # share of the pull speed kept when it ends

var weapon_nodes: Array[BaseWeapon] = []
var current_weapon: BaseWeapon
var weapon_index := 0

var current_movement_speed = base_movement_speed
var speed_multiplier := 1.0   # temporary boosts (the rifle's quickness), on top of walking or sliding speed
var gamepad_sensitivity := 0.075
var mouse_captured := true

var movement_velocity: Vector3
var rotation_target: Vector3
var input_mouse: Vector2

var health:int = 100
var cannot_die := false   # test room god mode: hits still land and lower health, but it stops at 1
var gravity := 0.0
var previously_floored := false

# Where a fall off the map puts the player back: the last spot they stood on with solid ground all around them
const SAFE_GROUND_CHECK_INTERVAL := 0.1
const SAFE_GROUND_MARGIN := 0.7       # floor needed this far out on every side, so they don't land on the very edge
const SAFE_GROUND_DEPTH := 1.0
const FALL_FADE_TIME := 0.4
const LANDING_CLEAR_RADIUS := 4.0     # enemies this close to the landing spot are shoved out to this distance
const LANDING_CLEAR_HEIGHT := 2.5
const LANDING_WAVE_SPEED := 30.0
var has_safe_ground := false
var safe_ground := Vector3.ZERO
var safe_ground_timer := 0.0
var fall_fade: ColorRect
var fall_fade_tween: Tween

var jump_single := true
var jump_double := true

var fall_distance = 0
var slide_speed = 0
var can_slide = false
var sliding = false
var falling = false
var play_slide_animation = false

var dashing = false
var dash_direction = Vector3.ZERO
var dash_time_left = 0.0
const DASH_CHARGES := 3
var dash_cooldowns: Array[float] = [0.0, 0.0, 0.0]   # seconds left until each dash is back (0 = ready)
var dash_recharging: Array[bool] = [false, false, false]   # a spent dash only starts coming back once the player touches the ground or a wall

var wall_jump_used := false
var last_wall_jump_normal := Vector3.ZERO
var wall_push_velocity := Vector3.ZERO
var wall_push_time_left := 0.0

var camera_kick := Vector2.ZERO
# Sustained camera shake: add_camera_shake() raises the trauma, which then decays on its own. The shake grows with
# the square of the trauma, so small hits barely register and big ones rattle the view.
var shake_trauma := 0.0
var shake_time := 0.0
const SHAKE_DECAY := 0.9           # trauma lost per second
const SHAKE_MAX_ANGLE := 0.075     # radians of pitch and yaw at full trauma
const SHAKE_MAX_ROLL := 0.06

# Set by the offhand shield: true while it is up (parry window or block), so projectiles can be absorbed
var shield_blocking := false
var push_impulse := Vector3.ZERO   # one-off shove from enemies, applied through the normal movement blend so it fades quickly
const BLOCK_DAMAGE_MULTIPLIER := 0.9         # damage taken while the shield is up (charges, blasts, shockwaves)
const BLOCK_MELEE_DAMAGE_MULTIPLIER := 0.5   # a melee blow (punch, lunge, sword) into the raised shield
var offhand_shield: Node

# Shield grapple: while true the player is pulled toward grapple_target and gravity is ignored
var grappling := false
var grapple_target := Vector3.ZERO
var grapple_direction := Vector3.ZERO
var grapple_velocity := Vector3.ZERO
var grapple_time := 0.0
var grapple_best_distance := INF
var grapple_stuck_time := 0.0

const DAMAGE_FLASH_SHADER: Shader = preload("res://shaders/player/damage_flash.gdshader")
const OFFHAND_SHIELD = preload("res://scripts/player/offhand_shield.gd")
var damage_flash_material: ShaderMaterial
var damage_flash_tween: Tween
var heal_flash_material: ShaderMaterial
var heal_flash_tween: Tween
const HEAL_FLASH_COLOR := Color(0.2, 1.0, 0.35, 1.0)


var tween:Tween

signal health_updated
signal damage_source(source)   # who or what just hurt the player: a Node3D or a world position
signal weapon_changed
signal key_collected(key: String)

var keys := {}   # colours of the level keys the player holds; a respawn gives back the ones held at the checkpoint

@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast
@onready var sound_footsteps = $SoundFootsteps
@onready var blaster_cooldown = $Cooldown
@onready var slide_check: RayCast3D = $SlideCheck
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@export var crosshair:TextureRect
@onready var weapon_holder = $Head/Camera/WeaponHolder
@onready var head: Node3D = $Head
@onready var psx_material: ShaderMaterial = $PSXOverlay/PSXRect.material

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_movement_speed = base_movement_speed

	raycast.enabled = true
	raycast.target_position = Vector3(0, 0, -100)
	raycast.collision_mask = (1 << 3) | (1 << 1)
	
	rotation_target = Vector3(camera.rotation.x, rotation.y, 0)
	for child in weapon_holder.get_children():
		if child is BaseWeapon:
			weapon_nodes.append(child)
			child.visible = false
			child.set_process(false)

	current_weapon = weapon_nodes[weapon_index]
	current_weapon.visible = true
	current_weapon.set_process(true)
	GlobalVariables.current_weapon = current_weapon.data.weapon_id
	GlobalVariables.player = self
	GlobalVariables.enemy_died.connect(_on_enemy_died_heal)
	psx_material.set_shader_parameter("effect_strength", GlobalVariables.psx_strength)
	psx_material.set_shader_parameter("vignette_strength", GlobalVariables.vignette_strength)
	_setup_damage_flash()
	_setup_heal_flash()
	_setup_fall_fade()
	offhand_shield = OFFHAND_SHIELD.new()
	camera.add_child(offhand_shield)
	crosshair.texture = current_weapon.data.crosshair
	weapon_changed.emit(current_weapon)

func _physics_process(delta):
	handle_controls(delta)
	handle_gravity(delta)

	if current_weapon:
		var is_walking = is_on_floor() and (
			Input.get_action_strength("move_forward") > 0.0 or
			Input.get_action_strength("move_back") > 0.0 or
			Input.get_action_strength("move_left") > 0.0 or
			Input.get_action_strength("move_right") > 0.0
		)
		current_weapon.set_movement_state(is_walking and not sliding)
		
	if falling and is_on_floor() and sliding:
		slide_speed += fall_distance / 10.0
	fall_distance = -gravity

	var touching := is_on_floor() or is_on_wall()
	for i in DASH_CHARGES:
		if dash_cooldowns[i] <= 0.0:
			continue
		if touching:
			dash_recharging[i] = true   # touching down starts it, and it carries on in the air
		if dash_recharging[i]:
			dash_cooldowns[i] = maxf(dash_cooldowns[i] - delta, 0.0)

	if dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			dashing = false

	if wall_push_time_left > 0.0:
		wall_push_time_left -= delta

	if grappling:
		_process_grapple(delta)

	movement_velocity = transform.basis * movement_velocity
	var applied_velocity: Vector3
	if grappling:
		applied_velocity = grapple_velocity
	elif dashing:
		applied_velocity = dash_direction * dash_speed
	elif wall_push_time_left > 0.0:
		applied_velocity = wall_push_velocity
	else:
		applied_velocity = velocity.lerp(movement_velocity, delta * 10) + Vector3(push_impulse.x, 0.0, push_impulse.z)
	push_impulse = Vector3.ZERO
	applied_velocity.y = -gravity
	velocity = applied_velocity
	move_and_slide()

	camera_kick = camera_kick.lerp(Vector2.ZERO, clampf(delta * kick_recovery, 0.0, 1.0))
	var shake := Vector3.ZERO
	if shake_trauma > 0.0:
		shake_time += delta * 38.0
		var amount := shake_trauma * shake_trauma
		shake = Vector3(
			sin(shake_time * 1.13) + 0.6 * sin(shake_time * 2.71 + 1.3),
			sin(shake_time * 0.97 + 2.1) + 0.6 * sin(shake_time * 2.37),
			sin(shake_time * 1.31 + 4.0)) * amount
		shake_trauma = move_toward(shake_trauma, 0.0, delta * SHAKE_DECAY)
	head.rotation.x = camera_kick.x + shake.x * SHAKE_MAX_ANGLE
	head.rotation.y = camera_kick.y + shake.y * SHAKE_MAX_ANGLE
	head.rotation.z = shake.z * SHAKE_MAX_ROLL

	camera.rotation.z = lerp_angle(camera.rotation.z, -input_mouse.x * 25 * delta, delta * 5)
	camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
	rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)

	sound_footsteps.stream_paused = true
	if is_on_floor():
		if (abs(velocity.x) > 1 or abs(velocity.z) > 1) and !sliding:
			sound_footsteps.stream_paused = false

	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	if is_on_floor() and gravity > 1 and !previously_floored:
		Audio.play("assets/audio/sfx/player/land.ogg")
		camera.position.y = -0.1

	previously_floored = is_on_floor()
	

	_update_safe_ground(delta)
	if has_safe_ground:
		if global_position.y < safe_ground.y - fall_reset_distance:
			_recover_from_fall()
	elif position.y < kill_height:
		Checkpoints.respawn()

func add_key(key: String) -> void:
	keys[key] = true
	key_collected.emit(key)


func has_key(key: String) -> bool:
	return keys.has(key)


func _update_safe_ground(delta: float) -> void:
	safe_ground_timer -= delta
	if safe_ground_timer > 0.0 or not is_on_floor():
		return
	safe_ground_timer = SAFE_GROUND_CHECK_INTERVAL
	for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		if not _is_solid_ground_below(global_position + offset * SAFE_GROUND_MARGIN):
			return
	safe_ground = global_position
	has_safe_ground = true


# Doors and other moving bodies don't count: they may not be there when the player comes back
func _is_solid_ground_below(point: Vector3) -> bool:
	var hit := PhysicsLayers.surface_ray(get_tree(), point + Vector3.UP * 0.5, point + Vector3.DOWN * SAFE_GROUND_DEPTH)
	return not hit.is_empty() and hit["collider"] is StaticBody3D


# Back to the last safe spot with a quick fade, minus some health, and straight back into the fight
func _recover_from_fall() -> void:
	grappling = false
	dashing = false
	wall_push_time_left = 0.0
	push_impulse = Vector3.ZERO
	velocity = Vector3.ZERO
	gravity = 0.0
	refresh_air_moves()
	global_position = safe_ground + Vector3.UP * 0.1
	reset_physics_interpolation()
	_clear_landing_spot()
	_play_fall_fade()
	damage(fall_damage)


func _clear_landing_spot() -> void:
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not enemy.has_method("shove_from"):
			continue
		var offset: Vector3 = enemy.global_position - safe_ground
		var flat_distance := Vector2(offset.x, offset.z).length()
		if flat_distance < LANDING_CLEAR_RADIUS and absf(offset.y) < LANDING_CLEAR_HEIGHT:
			enemy.shove_from(safe_ground, LANDING_CLEAR_RADIUS)
	BossShockwave.spawn(get_tree(), safe_ground, LANDING_CLEAR_RADIUS * 1.5, LANDING_WAVE_SPEED, 0.0, true)


func _play_fall_fade() -> void:
	fall_fade.color.a = 1.0
	if fall_fade_tween:
		fall_fade_tween.kill()
	fall_fade_tween = create_tween()
	fall_fade_tween.tween_property(fall_fade, "color:a", 0.0, FALL_FADE_TIME)


func _setup_fall_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	fall_fade = ColorRect.new()
	fall_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	fall_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fall_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fall_fade)


# Turns the player to face a world yaw, including the target the view eases towards
func set_facing(yaw: float) -> void:
	rotation.y = yaw
	rotation_target.y = yaw


func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		var sens = GlobalVariables.mouse_sensitivity * 0.0001
		rotation_target.y -= event.relative.x * sens
		rotation_target.x -= event.relative.y * sens


func handle_controls(_delta):
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true

	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
		
		input_mouse = Vector2.ZERO

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * current_movement_speed * speed_multiplier

	if Input.is_action_just_pressed("slide"):
		can_slide = true

	if Input.is_action_pressed("slide") and is_on_floor() and Input.is_action_pressed("move_forward") and can_slide:
		if !play_slide_animation:
			var slide_tween = create_tween()
			slide_tween.tween_property(self, "scale", Vector3(1.0, 0.8, 1.0), 0.2)
			play_slide_animation = true
		slide()

	if Input.is_action_just_released("slide"):
		var slide_tween = create_tween()
		slide_tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.2)
		play_slide_animation = false
		can_slide = false
		sliding = false
		current_movement_speed = base_movement_speed

	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	rotation_target -= Vector3(-rotation_input.y, -rotation_input.x, 0).limit_length(1.0) * gamepad_sensitivity
	rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))

	action_shoot()

	if grappling and Input.is_action_just_pressed("jump"):
		end_grapple(false)   # letting go with a jump; the jumps were refreshed when the shield latched on

	if Input.is_action_just_pressed("jump") and can_wall_jump():
		do_wall_jump()
	elif Input.is_action_just_pressed("jump"):
		if sliding:
			slide_speed -= 1

		if jump_single or jump_double:
			Audio.play("assets/audio/sfx/player/jump_a.ogg, assets/audio/sfx/player/jump_b.ogg, assets/audio/sfx/player/jump_c.ogg")
			

		if jump_double:
			gravity = -jump_strength
			jump_double = false

		if jump_single:
			action_jump()

	action_weapon_toggle()
	action_dash()

func handle_gravity(delta):
	gravity += 20 * delta
	falling = true

	if gravity > 0 and is_on_floor():
		jump_single = true
		wall_jump_used = false
		falling = false
		gravity = 0

func slide():
	# Get current floor angle and normal
	var floor_angle = get_floor_angle()
	var floor_normal = get_floor_normal()
	
	if not sliding:
		# Initialize slide speed
		print("Starting slide - Floor angle (degrees): ", rad_to_deg(floor_angle))
		
		# Can only start sliding if there's room or on a slope
		if slide_check.is_colliding():
			print("Blocked - can't slide!")
			can_slide = false
			return
		
		# Start with base speed + momentum from falling
		slide_speed = base_slide_speed + (fall_distance / 10.0)
		sliding = true
	
	# Calculate if we're going downhill by checking movement direction vs slope
	var movement_dir = -transform.basis.z  # Forward direction
	var slope_direction = Vector3(floor_normal.x, 0, floor_normal.z).normalized()
	var going_downhill = movement_dir.dot(slope_direction) > 0
	
	# Apply slope physics
	if floor_angle > 0.1:  # On a slope (> ~5.7 degrees)
		if going_downhill:
			# Going downhill = gain speed
			slide_speed += floor_angle * 15.0 * get_physics_process_delta_time()
		else:
			# Going uphill = lose speed faster
			slide_speed -= floor_angle * 20.0 * get_physics_process_delta_time()
	else:
		# Flat ground = lose speed due to friction
		slide_speed -= 3.0 * get_physics_process_delta_time()
	
	# Clamp speed
	slide_speed = clamp(slide_speed, 0, max_slide_speed)
	
	# Stop sliding if too slow
	if slide_speed < 1.0:
		can_slide = false
		sliding = false
		slide_speed = 0
		current_movement_speed = base_movement_speed
		return

	current_movement_speed = slide_speed


# Wall jump is its own jump: it never consumes or restores the double jump.
# One per airtime, but touching a different wall (zig-zagging) makes it available again.
func can_wall_jump() -> bool:
	if is_on_floor() or not is_on_wall_only():
		return false
	if not wall_jump_used:
		return true
	return get_wall_normal().dot(last_wall_jump_normal) < 0.5

func do_wall_jump() -> void:
	var normal := get_wall_normal()
	normal.y = 0.0
	normal = normal.normalized()

	gravity = -wall_jump_strength
	wall_push_velocity = normal * wall_jump_push
	wall_push_time_left = wall_jump_push_time
	wall_jump_used = true
	last_wall_jump_normal = normal
	Audio.play("assets/audio/sfx/player/jump_a.ogg, assets/audio/sfx/player/jump_b.ogg, assets/audio/sfx/player/jump_c.ogg")

func action_jump():
	gravity = -jump_strength
	jump_single = false
	jump_double = true

func action_shoot():
	if Input.is_action_pressed("shoot"):
		if !blaster_cooldown.is_stopped():
			return
		blaster_cooldown.start(current_weapon.data.cooldown)
		current_weapon.fire(global_transform.origin, -camera.global_transform.basis.z, camera, raycast)

func action_dash():
	if grappling and Input.is_action_just_pressed("dash"):
		end_grapple(false)

	var ready_dash := dash_cooldowns.find_custom(func(left: float): return left <= 0.0)
	if Input.is_action_just_pressed("dash") and ready_dash != -1:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var local_direction: Vector3
		if input.length() > 0.1:
			local_direction = Vector3(input.x, 0, input.y).normalized()
		else:
			local_direction = Vector3(0, 0, -1)

		dash_direction = (transform.basis * local_direction).normalized()
		dashing = true
		dash_time_left = dash_duration
		dash_cooldowns[ready_dash] = dash_cooldown
		dash_recharging[ready_dash] = false
		Audio.play("assets/audio/sfx/player/simple_whoosh.mp3")

# ---------------------------
# Shield grapple
# ---------------------------
# Gives back everything the player spends in the air: both jumps, the wall jump and the dash
func refresh_air_moves() -> void:
	jump_single = true
	jump_double = true
	wall_jump_used = false
	dash_cooldowns.fill(0.0)
	dash_recharging.fill(false)


func start_grapple(point: Vector3) -> void:
	grappling = true
	grapple_target = point
	grapple_time = 0.0
	grapple_best_distance = INF
	grapple_stuck_time = 0.0
	dashing = false
	wall_push_time_left = 0.0
	refresh_air_moves()


func _process_grapple(delta: float) -> void:
	var to_point: Vector3 = grapple_target - camera.global_position
	var distance := to_point.length()
	grapple_time += delta

	if distance <= grapple_arrive_distance:
		end_grapple(true)
		return

	grapple_direction = to_point / distance
	# Give up when something blocks the way (no progress toward the point) or it takes too long
	if distance < grapple_best_distance - 0.02:
		grapple_best_distance = distance
		grapple_stuck_time = 0.0
	else:
		grapple_stuck_time += delta
	if grapple_stuck_time > 0.2 or grapple_time > grapple_max_time:
		end_grapple(false)
		return

	grapple_velocity = grapple_direction * grapple_speed
	gravity = -grapple_velocity.y     # the vertical part of the pull goes through the gravity variable


# Ends the pull, keeping some of the speed so the player flies on a little. arrived = reached the point.
func end_grapple(arrived: bool) -> void:
	if not grappling:
		return
	grappling = false
	var carry := grapple_direction * grapple_speed * grapple_release_carry
	velocity = Vector3(carry.x, 0.0, carry.z)
	gravity = -carry.y
	if arrived:
		refresh_air_moves()


func apply_camera_kick(pitch: float, yaw: float) -> void:
	camera_kick += Vector2(pitch, yaw)


# A sustained rattle of the view that fades out by itself (0..1; stacks, capped at 1)
func add_camera_shake(trauma: float) -> void:
	shake_trauma = minf(shake_trauma + trauma, 1.0)

func action_weapon_toggle():
	if Input.is_action_just_pressed("weapon_toggle"):
		change_weapon((weapon_index + 1) % weapon_nodes.size())

	if Input.is_action_just_pressed("weapon_1") and weapon_nodes.size() >= 1:
		change_weapon(0)
	if Input.is_action_just_pressed("weapon_2") and weapon_nodes.size() >= 2:
		change_weapon(1)
	if Input.is_action_just_pressed("weapon_3") and weapon_nodes.size() >= 3:
		change_weapon(2)
	if Input.is_action_just_pressed("weapon_4") and weapon_nodes.size() >= 4:
		change_weapon(3)
	if Input.is_action_just_pressed("weapon_5") and weapon_nodes.size() >= 5:
		change_weapon(4)

func change_weapon(index, play_sound := true):
	if index == weapon_index or index < 0 or index >= weapon_nodes.size():
		return

	# Disable currently equipped weapon
	weapon_nodes[weapon_index].visible = false
	weapon_nodes[weapon_index].set_process(false)

	# Activate weapon you are swapping to 
	weapon_index = index
	current_weapon = weapon_nodes[weapon_index]
	current_weapon.visible = true
	current_weapon.set_process(true)
	crosshair.texture = current_weapon.data.crosshair
	if play_sound:
		Audio.play("assets/audio/sfx/weapons/weapon_change.ogg")
	GlobalVariables.current_weapon = current_weapon.data.weapon_id
	weapon_changed.emit(current_weapon)

func _setup_damage_flash() -> void:
	# Screen-edge red vignette; layer 0 keeps it under the HUD so health stays readable.
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)

	damage_flash_material = ShaderMaterial.new()
	damage_flash_material.shader = DAMAGE_FLASH_SHADER
	# Wider, brighter edge than the shader's defaults so hits are easy to notice
	damage_flash_material.set_shader_parameter("edge_power", 1.6)
	damage_flash_material.set_shader_parameter("inner_ratio", 0.6)
	damage_flash_material.set_shader_parameter("feather", 0.5)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = damage_flash_material
	layer.add_child(rect)

# The green counterpart of the red hit vignette: the same screen-edge shader, on its own layer so a heal and a hit
# can show at the same time, and a little softer and slower since it is good news
func _setup_heal_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)

	heal_flash_material = ShaderMaterial.new()
	heal_flash_material.shader = DAMAGE_FLASH_SHADER
	heal_flash_material.set_shader_parameter("flash_color", HEAL_FLASH_COLOR)
	heal_flash_material.set_shader_parameter("edge_power", 1.6)
	heal_flash_material.set_shader_parameter("inner_ratio", 0.6)
	heal_flash_material.set_shader_parameter("feather", 0.5)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = heal_flash_material
	layer.add_child(rect)


# Called when something heals the player visibly (the medkit pickup)
# Every kill drops health packs worth its kill_heal; the kill itself heals nothing. Killed from really close, the
# packs fly straight to you and heal on arrival; killed from further away, they fall to the floor to be picked up.
func _on_enemy_died_heal(enemy: Node3D) -> void:
	if not is_instance_valid(enemy) or health <= 0 or enemy.get("grants_kill_heal") != true:
		return
	var amount: int = enemy.get("kill_heal") if enemy.get("kill_heal") != null else 0
	if amount <= 0:
		return
	var point := enemy.global_position + Vector3.UP
	# A player already at full health has nothing to heal, so the packs wait on the floor for later
	var homing: bool = health < 100 and camera.global_position.distance_to(point) <= kill_heal_range
	KillHealPack.spawn(get_tree(), point, self, amount, homing)


func play_heal_flash() -> void:
	if heal_flash_material == null:
		return
	var peak := 0.75
	heal_flash_material.set_shader_parameter("intensity", peak)
	if heal_flash_tween:
		heal_flash_tween.kill()
	heal_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	heal_flash_tween.tween_method(_set_heal_flash_intensity, peak, 0.0, heal_flash_time)


func _set_heal_flash_intensity(value: float) -> void:
	heal_flash_material.set_shader_parameter("intensity", value)


func _play_damage_flash(amount) -> void:
	if damage_flash_material == null or amount <= 0:
		return
	# Bigger hits flash harder
	var peak := clampf(0.8 + float(amount) * 0.01, 0.8, 1.0)
	damage_flash_material.set_shader_parameter("intensity", peak)
	if damage_flash_tween:
		damage_flash_tween.kill()
	damage_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	damage_flash_tween.tween_method(_set_damage_flash_intensity, peak, 0.0, damage_flash_time)

func _set_damage_flash_intensity(value: float) -> void:
	damage_flash_material.set_shader_parameter("intensity", value)

# Shoves the player (horizontal velocity, in units per second)
func apply_push(impulse: Vector3) -> void:
	push_impulse += impulse


# `melee`: a blow from an enemy's fist or blade, which the raised shield takes more of
# `source`: what hit you, a Node3D (followed while it lives) or a world position (an explosion's centre), for the
# damage direction indicator. Left out, no indicator shows.
func damage(amount, melee := false, source = null):
	if shield_blocking:
		amount *= BLOCK_MELEE_DAMAGE_MULTIPLIER if melee else BLOCK_DAMAGE_MULTIPLIER
	health -= amount
	if cannot_die:
		health = maxi(health, 1)
	_play_damage_flash(amount)
	health_updated.emit(health)
	if source != null:
		damage_source.emit(source)
	if health <= 0:
		GameManager.player_died()
