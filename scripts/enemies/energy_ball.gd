extends Area3D

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D

@export var SPEED := 10.0
@export var damage := 10
@export var turn_rate := 2.0  # radians per second
@export var target_path: NodePath

var target: Node3D
var velocity: Vector3

func _ready():
	if target_path != NodePath():
		target = get_node_or_null(target_path)

	velocity = global_transform.basis.z * SPEED

func _physics_process(delta):
	if is_instance_valid(target):
		var to_target = (target.global_position - global_position).normalized()
		velocity = velocity.slerp(to_target * SPEED, turn_rate * delta)

	global_position += velocity * delta

	# Make sure it visually faces the direction of travel
	look_at(global_position + velocity.normalized(), Vector3.UP)


func _on_body_entered(body):
	if body.is_in_group("Player") and body.has_method("damage"):
		Audio.play("sounds/enemy_attack.ogg")
		body.damage(damage)
	queue_free()


func _on_self_queue_timer_timeout():
	queue_free()
