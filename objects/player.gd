extends CharacterBody3D

@export_subgroup("Properties")
@export var base_movement_speed = 5
@export var base_slide_speed = 7
@export var jump_strength = 8
@export var max_slide_speed = 8

@onready var weapon_holder = $Head/Camera/WeaponHolder

var weapon_nodes: Array[BaseWeapon] = []
var current_weapon: BaseWeapon
var weapon_index := 0

var current_movement_speed = base_movement_speed
var mouse_sensitivity = 700
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

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_movement_speed = base_movement_speed

	raycast.enabled = true
	raycast.target_position = Vector3(0, 0, -100)
	
	rotation_target = Vector3(camera.rotation.x, rotation.y, 0)
	for child in weapon_holder.get_children():
		if child is BaseWeapon:
			weapon_nodes.append(child)
			child.visible = false
			child.set_process(false)

	current_weapon = weapon_nodes[weapon_index]
	current_weapon.visible = true
	current_weapon.set_process(true)
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
		current_weapon.set_movement_state(is_walking)
		
	if falling and is_on_floor() and sliding:
		slide_speed += fall_distance / 10
	fall_distance = -gravity

	movement_velocity = transform.basis * movement_velocity
	var applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = -gravity
	velocity = applied_velocity
	move_and_slide()

	camera.rotation.z = lerp_angle(camera.rotation.z, -input_mouse.x * 25 * delta, delta * 5)
	camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
	rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)

	sound_footsteps.stream_paused = true
	if is_on_floor():
		if (abs(velocity.x) > 1 or abs(velocity.z) > 1) and !sliding:
			sound_footsteps.stream_paused = false

	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	if is_on_floor() and gravity > 1 and !previously_floored:
		Audio.play("sounds/land.ogg")
		camera.position.y = -0.1

	previously_floored = is_on_floor()
	

	if position.y < -10:
		get_tree().reload_current_scene()

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		rotation_target.y -= event.relative.x / mouse_sensitivity
		rotation_target.x -= event.relative.y / mouse_sensitivity

func handle_controls(_delta):
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true

	if Input.is_action_just_pressed("mouse_capture_exit"):
		get_tree().quit()

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

	if Input.is_action_just_pressed("jump"):
		if sliding:
			slide_speed -= 1

		if jump_single or jump_double:
			Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
			

		if jump_double:
			gravity = -jump_strength
			jump_double = false

		if jump_single:
			action_jump()

	action_weapon_toggle()

func handle_gravity(delta):
	gravity += 20 * delta
	falling = true

	if gravity > 0 and is_on_floor():
		jump_single = true
		falling = false
		gravity = 0

func slide():
	if not sliding:
		if slide_check.is_colliding() or get_floor_angle() < 0.2:
			slide_speed = base_slide_speed
			slide_speed += fall_distance / 10
		else:
			slide_speed = 1

	sliding = true

	if slide_check.is_colliding():
		slide_speed += get_floor_angle() / 10
	else:
		slide_speed -= (get_floor_angle() / 5) + 0.1

	if slide_speed > max_slide_speed:
		slide_speed = max_slide_speed

	if slide_speed < 0:
		can_slide = false
		sliding = false

	current_movement_speed = slide_speed

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
	Audio.play("sounds/weapon_change.ogg")
	weapon_changed.emit(current_weapon)

func damage(amount):
	health -= amount
	health_updated.emit(health)
	if health <= 0:
		get_tree().reload_current_scene()
