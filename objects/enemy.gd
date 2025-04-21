extends CharacterBody3D

@export var player: Node3D

@onready var raycast = $RayCast
@onready var energy_ball_spawn_marker = $EnergyBallSpawnMarker
#@onready var muzzle_a = $MuzzleA
#@onready var muzzle_b = $MuzzleB

var health := 100
var time := 0.0
var destroyed := false
var energy_ball = load("res://objects/energy_ball.tscn")


# When ready, save the initial position
func _ready():
	energy_ball_spawn_marker.position = global_position

func _process(delta):
	self.look_at(player.position + Vector3(0, 0.5, 0), Vector3.UP, true)  # Look at player

	time += delta


# Take damage from player
func damage(amount):
	Audio.play("sounds/enemy_hurt.ogg")

	health -= amount

	if health <= 0 and !destroyed:
		destroy()

# Destroy the enemy when out of healt
func destroy():
	Audio.play("sounds/enemy_destroy.ogg")

	destroyed = true
	queue_free()

# Shoot when timer hits 0
func _on_timer_timeout():
	raycast.force_raycast_update()

	if raycast.is_colliding():
		var collider = raycast.get_collider()

		if collider.has_method("damage"):  # Raycast collides with player
			
			# Play muzzle flash animation(s)
			#muzzle_a.frame = 0
			#muzzle_a.play("default")
			#muzzle_a.rotation_degrees.z = randf_range(-45, 45)
#
			#muzzle_b.frame = 0
			#muzzle_b.play("default")
			#muzzle_b.rotation_degrees.z = randf_range(-45, 45)

			Audio.play("sounds/enemy_attack.ogg")

			collider.damage(5)  # Apply damage to player
