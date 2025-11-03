extends Area3D

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D

@export var SPEED : float = 10.0
@export var damage : float= 10
@export var turn_rate : float = 2.0  # radians per second

var target: Node3D
var velocity: Vector3


func _ready():
	velocity = global_transform.basis.z * SPEED


func _physics_process(delta):
	if not is_instance_valid(target):
		global_position += velocity * delta
		return

	# Homing calculation
	var to_target = (target.global_position - global_position).normalized()
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
		Audio.play("sounds/enemy_attack.ogg")
		body.damage(damage)
	queue_free()


func _on_self_queue_timer_timeout():
	queue_free()
