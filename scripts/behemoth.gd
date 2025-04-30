extends CharacterBody3D


@onready var animated_sprite_3d = $AnimatedSprite3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

@export var move_speed = 2.0
@export var attack_range = 2.0

@onready var player : CharacterBody3D = get_tree().get_first_node_in_group("player")
@onready var attack_cooldown: Timer = $AttackCooldown

var dead : bool = false
var can_attack : bool = true
var player_detected : bool = false

@export var health = 300
var max_health = 300
var direction

func _physics_process(delta):
	if dead:
		return
	if player == null:
		return
	
	if not player_detected:
		# Direction is set towards the player
		direction = player.global_position - global_position
		direction.y = 0.0
		direction = direction.normalized()
		animation_player.play("walk")
		# Moves towards player
		velocity = direction * move_speed

	move_and_slide()
	attempt_to_kill_player()

func attempt_to_kill_player():
	var dist_to_player = global_position.distance_to(player.global_position)
	if dist_to_player > attack_range:
		return
	
	var eye_line = Vector3.UP * 1.5
	var query = PhysicsRayQueryParameters3D.create(global_position+eye_line, player.global_position + eye_line, 1)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	
	# Player is within attack range
	if result.is_empty():
		player_detected = true
		velocity = Vector3.ZERO
		if can_attack:
			attack_cooldown.start()
			animation_player.play("attack")
			can_attack = false

func enemy_take_damage(damage):
	health -= damage
	health = clamp(health, 0, max_health)
	
	
	hit_flash()
	if health <= 0 && !dead:
		kill()
	
func kill():
	dead = true
	#$DeathSound.play()
	animation_player.play("death")
	$CollisionShape3D.disabled = true


func _on_attack_cooldown_timeout() -> void:
	can_attack = true
	player_detected = false

func behemoth_melee(damage : int):
	player.take_damage(damage)

func hit_flash():
	var tween = get_tree().create_tween()
	tween.tween_property($AnimatedSprite3D, "modulate", Color.RED, 0.1)
	tween.tween_property($AnimatedSprite3D, "scale", Vector2(), 1)
	tween.tween_property($AnimatedSprite3D, "modulate", Color.WHITE,0.1)
	#tween.tween_callback($AnimatedSprite3D.queue_free)
