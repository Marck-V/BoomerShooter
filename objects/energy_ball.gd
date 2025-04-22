extends Area3D

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D

@export var SPEED := 10.0

func _ready():
	pass
	
func _physics_process(delta):
	position += transform.basis * Vector3(0, 0, SPEED) * delta
	

func _on_body_entered(body):
	if body.has_method("damage"):
		Audio.play("sounds/enemy_attack.ogg")
#
		body.damage(40)  # Apply damage to player
	
	queue_free()

# Destroy itself if it never collides
func _on_self_queue_timer_timeout():
	queue_free()
