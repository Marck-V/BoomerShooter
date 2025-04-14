extends CharacterBody3D

@export var movement_speed: float = 2.0
@export var movement_target_position: CharacterBody3D
@export var damage_to_player: float = 50

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_player = $"enemy-humanoid/AnimationPlayer"
@onready var hit_raycast = $HitRaycast
@onready var bite_timer = $BiteTimer

var reached_target : bool = false
var health : int = 100
var destroyed : bool = false

func _ready():
	# Make sure to not await during _ready.
	actor_setup.call_deferred()

func actor_setup():
	# Wait for the first physics frame so the NavigationServer can sync.
	await get_tree().physics_frame

	# Now that the navigation map is no longer empty, set the movement target.
	set_movement_target(movement_target_position.global_position)

func set_movement_target(movement_target: Vector3):
	navigation_agent.set_target_position(movement_target)

func _physics_process(_delta):
	if navigation_agent.is_navigation_finished():
		reached_target = true
		print("Player reached... bite!")
		bite()
	else:
		reached_target = false
		
	handle_animations()
	
	# Update the target location to player's current location
	var current_agent_position: Vector3 = global_position
	set_movement_target(movement_target_position.global_position)
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()

	velocity = current_agent_position.direction_to(next_path_position) * movement_speed
	
	look_at(Vector3(movement_target_position.global_position.x, global_position.y, movement_target_position.global_position.z), Vector3.UP, true)
	
	move_and_slide()

func handle_animations():
	if reached_target:
		animation_player.play("Bite")
	else:
		animation_player.play("Run")

# Take damage from player
func damage(amount):
	Audio.play("sounds/enemy_hurt.ogg")

	health -= amount

	if health <= 0 and !destroyed:
		destroy()

func destroy():
	Audio.play("sounds/enemy_destroy.ogg")

	destroyed = true
	queue_free()
	
func bite():
	if !bite_timer.is_stopped():
		return
	
	hit_raycast.force_raycast_update()

	if hit_raycast.is_colliding():
		var collider = hit_raycast.get_collider()

		if collider.has_method("damage"):  # Raycast collides with player
			Audio.play("sounds/enemy_attack.ogg")

			collider.damage(damage_to_player)  # Apply damage to player
			
		bite_timer.start()
