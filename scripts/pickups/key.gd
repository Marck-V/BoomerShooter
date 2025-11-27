extends Area3D
class_name KeyPickup

@onready var key_mesh: MeshInstance3D = $Key

func _process(delta):
	key_mesh.rotate_y(delta)
