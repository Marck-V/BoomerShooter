extends Node3D



func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		print("Player picked up gold bar.")
		GlobalVariables.add_points(99)
		Audio.play("sounds/money_pickup.mp3")
		queue_free()
