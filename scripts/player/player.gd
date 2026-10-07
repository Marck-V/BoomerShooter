extends CharacterBody3D

@export_subgroup("Properties")
@export var base_movement_speed = 10
@export var base_slide_speed = 10
@export var jump_strength = 8
@export var max_slide_speed = 12
@export var mouse_sensitivity = 20
@export var dash_speed = 25
@export var dash_duration = 0.2
@export var dash_cooldown = 0.75
@export var wall_jump_strength = 8
@export var wall_jump_push = 10.0
@export var wall_jump_push_time = 0.2
@export var kick_recovery = 14.0
@export var damage_flash_time = 0.4

var weapon_nodes: Array[BaseWeapon] = []
var current_weapon: BaseWeapon
var weapon_index := 0

var current_movement_speed = base_movement_speed
var gamepad_sensitivity := 0.075
var mouse_captured := true

var movement_velocity: Vector3
var rotation_target: Vector3
var input_mouse: Vector2

var health:int = 100
var gravity := 0.0
var previously_floored := false

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
var dash_cooldown_left = 0.0

var wall_jump_used := false
var last_wall_jump_normal := Vector3.ZERO
var wall_push_velocity := Vector3.ZERO
var wall_push_time_left := 0.0

var camera_kick := Vector2.ZERO

const DAMAGE_FLASH_SHADER: Shader = preload("res://shaders/damage_flash.gdshader")
var damage_flash_material: ShaderMaterial
var damage_flash_tween: Tween


var tween:Tween

signal health_updated
signal weapon_changed

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
	psx_material.set_shader_parameter("effect_strength", GlobalVariables.psx_strength)
	_setup_damage_flash()
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

	if dash_cooldown_left > 0.0:
		dash_cooldown_left -= delta

	if dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			dashing = false

	if wall_push_time_left > 0.0:
		wall_push_time_left -= delta

	movement_velocity = transform.basis * movement_velocity
	var applied_velocity: Vector3
	if dashing:
		applied_velocity = dash_direction * dash_speed
	elif wall_push_time_left > 0.0:
		applied_velocity = wall_push_velocity
	else:
		applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = -gravity
	velocity = applied_velocity
	move_and_slide()

	camera_kick = camera_kick.lerp(Vector2.ZERO, clampf(delta * kick_recovery, 0.0, 1.0))
	head.rotation.x = camera_kick.x
	head.rotation.y = camera_kick.y

	camera.rotation.z = lerp_angle(camera.rotation.z, -input_mouse.x * 25 * delta, delta * 5)
	camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
	rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)

	sound_footsteps.stream_paused = true
	if is_on_floor():
		if (abs(velocity.x) > 1 or abs(velocity.z) > 1) and !sliding:
			sound_footsteps.stream_paused = false

	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	if is_on_floor() and gravity > 1 and !previously_floored:
		Audio.play("assets/sounds/land.ogg")
		camera.position.y = -0.1

	previously_floored = is_on_floor()
	

	if position.y < -20:
		get_tree().reload_current_scene()

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
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * current_movement_speed

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
	action_alt_fire()

	if Input.is_action_just_pressed("jump") and can_wall_jump():
		do_wall_jump()
	elif Input.is_action_just_pressed("jump"):
		if sliding:
			slide_speed -= 1

		if jump_single or jump_double:
			Audio.play("assets/sounds/jump_a.ogg, assets/sounds/jump_b.ogg, assets/sounds/jump_c.ogg")
			

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
	Audio.play("assets/sounds/jump_a.ogg, assets/sounds/jump_b.ogg, assets/sounds/jump_c.ogg")

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
		current_weapon.trigger_recoil()

func action_alt_fire():
	if current_weapon.has_method("alt_fire"):
		if Input.is_action_just_pressed("alt_fire"):
			current_weapon.alt_fire(global_transform.origin, -camera.global_transform.basis.z, camera, raycast)

func action_dash():
	if Input.is_action_just_pressed("dash") and dash_cooldown_left <= 0.0:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var local_direction: Vector3
		if input.length() > 0.1:
			local_direction = Vector3(input.x, 0, input.y).normalized()
		else:
			local_direction = Vector3(0, 0, -1)

		dash_direction = (transform.basis * local_direction).normalized()
		dashing = true
		dash_time_left = dash_duration
		dash_cooldown_left = dash_cooldown
		Audio.play("assets/sounds/simple_whoosh.mp3")

func apply_camera_kick(pitch: float, yaw: float) -> void:
	camera_kick += Vector2(pitch, yaw)

func action_weapon_toggle():
	if Input.is_action_just_pressed("weapon_toggle"):
		change_weapon((weapon_index + 1) % weapon_nodes.size())

	if Input.is_action_just_pressed("weapon_1") and weapon_nodes.size() >= 1:
		change_weapon(0)
	if Input.is_action_just_pressed("weapon_2") and weapon_nodes.size() >= 2:
		change_weapon(1)
	if Input.is_action_just_pressed("weapon_3") and weapon_nodes.size() >= 3:
		change_weapon(2)

func change_weapon(index):
	if index == weapon_index:
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
	Audio.play("assets/sounds/weapon_change.ogg")
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

func damage(amount):
	health -= amount
	_play_damage_flash(amount)
	health_updated.emit(health)
	if health <= 0:
		GameManager.player_died()
