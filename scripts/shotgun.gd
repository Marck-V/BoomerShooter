extends BaseWeapon

@onready var tween := create_tween()

func fire(origin: Vector3, direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	# Call the original BaseWeapon fire logic
	super.fire(origin, direction, camera, raycast)

	# Reset rotation and tween
	rotation_degrees.x = 0
	tween.kill()  # Stop any ongoing tween

	# Add a 360° backflip around the X axis
	tween = create_tween()
	tween.tween_property(self, "rotation_degrees:x", -360.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(self, "_reset_rotation"))

func _reset_rotation():
	rotation_degrees.x = 0  
