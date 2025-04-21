extends RigidBody3D

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D

@export var SPEED := 10.0

func _ready():
	pass
	
func _physics_process(delta):
	position += transform.basis * Vector3(0, 0, SPEED) * delta
