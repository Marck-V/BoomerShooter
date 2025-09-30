extends CharacterBody3D

@export var movement_speed: float = 2.0
@export var firing_target_offset := -0.1
@export var firing_rate := 5
@export var shoot_range := 10
@export var health := 100

@onready var raycast = $RayCast
@onready var energy_ball_spawn_marker = $EnergyBallSpawnMarker
@onready var shoot_timer = $ShootTimer

@onready var navigation_agent = $NavigationAgent3D
@export var movement_target_position: CharacterBody3D

var destroyed := false
var energy_ball = load("res://scenes/enemies/energy_ball.tscn")
var death_sound : String = "assets/sounds/enemy_hurt.ogg"

func _ready():
	# Make sure to not await during _ready.
	actor_setup.call_deferred()
	raycast.target_position = Vector3(0, 0, shoot_range)
	shoot_timer.wait_time = firing_rate

func actor_setup():
	# Wait for the first physics frame so the NavigationServer can sync.
	await get_tree().physics_frame

	# Now that the navigation map is no longer empty, set the movement target.
	set_movement_target(movement_target_position.global_position)

func set_movement_target(movement_target: Vector3):
	navigation_agent.set_target_position(movement_target)
	
func _physics_process(_delta):
	# Update the target location to player's current location
	var current_agent_position: Vector3 = global_position
	set_movement_target(movement_target_position.global_position)
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	
	self.look_at(Vector3(movement_target_position.global_position.x, global_position.y, movement_target_position.global_position.z - firing_target_offset), Vector3.UP, true)  # Look at player
	
	# If enemy is range, then stop and shoot, else get in range
	if navigation_agent.distance_to_target() <= shoot_range:
		if shoot_timer.is_stopped():
			shoot_energy_ball()
			shoot_timer.start()
		return
	else:
		velocity = current_agent_position.direction_to(next_path_position) * movement_speed

		move_and_slide()

# Take damage from player
func damage(amount):
	Audio.play(death_sound)

	health -= amount

	if health <= 0 and !destroyed:
		destroy()

# Destroy the enemy when out of healt
func destroy():
	Audio.play(death_sound)
	
	destroyed = true
	queue_free()

# Shoot when timer hits 0
func _on_timer_timeout():
	raycast.force_raycast_update()

	if raycast.is_colliding():
		# print("Locked onto target.")
		var _collider = raycast.get_collider()
		
		shoot_energy_ball()

func shoot_energy_ball():
	var energy_ball_instance = energy_ball.instantiate() as Area3D
	energy_ball_instance.position = energy_ball_spawn_marker.global_position
	energy_ball_instance.transform.basis = energy_ball_spawn_marker.global_basis
	get_parent().add_child(energy_ball_instance)
