extends Area3D

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D

@export var SPEED : float = 10.0
@export var damage : float = 10
@export var turn_rate : float = 2.0  # radians per second
@export var target_offset = Vector3(0.0, 1.0, 0.0)

@export var max_scale: float = 2.0
@export var scale_speed: float = 1.0

var scale_progress: float = 0.0
var target: Node3D
var velocity: Vector3


func _ready():
	velocity = global_transform.basis.z * SPEED


func _physics_process(delta):
	# ----- Projectile Scaling -----
	if scale_progress < 1.0:
		scale_progress = min(scale_progress + scale_speed * delta, 1.0)
		var scale_value = lerp(1.0, max_scale, scale_progress)
		scale = Vector3.ONE * scale_value

	if not is_instance_valid(target):
		global_position += velocity * delta
		return

	# Homing calculation
	var to_target = (target.global_position + target_offset - global_position).normalized()
	var turn_strength = clamp(turn_rate * delta / velocity.length(), 0, 1)
	velocity = velocity.slerp(to_target * SPEED, turn_strength)

	# Move projectile
	global_position += velocity * delta

	# Face direction of travel
	if velocity.length() > 0.01:
		look_at(global_position + velocity.normalized(), Vector3.UP)


func set_target(t: Node3D) -> void:
	target = t


func _on_body_entered(body):
	if body.is_in_group("Player") and body.has_method("damage"):
		Audio.play("assets/audio/sfx/enemies/Enemy_ProjectileHit1.wav,
						   assets/audio/sfx/enemies/Enemy_ProjectileHit2.wav")
		body.damage(damage)
	queue_free()


func _on_self_queue_timer_timeout():
	queue_free()
