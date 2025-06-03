extends Node

var has_key = false
var door2_unlocked = false  # Flag to track if door2 has been unlocked
@onready var upgrade_station: Node3D = $"../UpgradeStation"
@onready var player: CharacterBody3D = $"../Player"
var upgrade_station_camera
var player_camera
var area_occupied


func _ready() -> void:
	upgrade_station.get_node("Area3D").connect("body_entered", on_upgrade_station_body_entered)
	upgrade_station.get_node("Area3D").connect("body_exited", on_upgrade_station_body_exited)
	upgrade_station_camera = upgrade_station.get_node("Camera3D")
	player_camera = player.get_node("Head/Camera")
	
func _process(delta):
	if has_key:
		unlock_door()
	else:
		if not door2_unlocked and get_enemy_count() == 0:  # Check if door2 is already unlocked
			
			door2_unlocked = true  # Set the flag to prevent further calls
			print("All enemies defeated, door unlocked.")

	if Input.is_action_just_pressed("interact") and area_occupied:
			player_camera.clear_current()
			upgrade_station_camera.make_current()
			
			
	if Input.is_action_just_pressed("back") and area_occupied:
		upgrade_station_camera.clear_current()
		player_camera.make_current()
			
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
		area_occupied = true
		
		
func on_upgrade_station_body_exited(body):
	if body.is_in_group("Player"):
		print(body)
		area_occupied = false

	
