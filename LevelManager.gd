extends Node

var has_key = false
var door2_unlocked = false  # Flag to track if door2 has been unlocked
@onready var upgrade_station: Node3D = $"../UpgradeStation"


func _ready() -> void:
	upgrade_station.get_node("Area3D").connect("body_entered", on_upgrade_station_body_entered)
	
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

func on_upgrade_station_body_entered(body):
	if body.is_in_group("Player"):
		print(body)
