extends Node

var has_key = false
var door2_unlocked = false  # Flag to track if door2 has been unlocked

func _process(delta):
	if has_key:
		unlock_door()
	else:
		if not door2_unlocked and get_enemy_count() == 0:  # Check if door2 is already unlocked
			
			door2_unlocked = true  # Set the flag to prevent further calls
			print("All enemies defeated, door unlocked.")

func _on_key_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print(body)
		has_key = true
		#key.queue_free()

func unlock_door():
	#door.queue_free()
	has_key = false
	
func get_enemy_count():
	var enemies = get_node("../Enemies")
	return enemies.get_child_count()
