extends Node

@onready var upgrade_station: Node3D = $"../UpgradeStation"
@onready var player: CharacterBody3D = $"../Player"
@onready var hud = $"../HUD"
@onready var interact_box = $"../HUD/InGameHUD/InteractContainer"
@onready var red_key_zone: Area3D = $"../KeyCheckAreas/RedKeyZone"
@onready var blue_key_zone: Area3D = $"../KeyCheckAreas/BlueKeyZone"
@onready var red_key: Node3D = $"../RedKeyArea"
@onready var blue_key: Node3D = $"../BlueKeyArea"
@onready var red_key_barrier = $"../RedKeyArea/Barrier"
@onready var blue_key_barrier = $"../BlueKeyArea/Barrier"
@onready var enter_boss_area: Area3D = $"../EnterBossArea"
@onready var audio_player: AudioStreamPlayer = $"../AudioStreamPlayer"
@onready var boss_music_player: AudioStreamPlayer = $"../BossMusicPlayer"

# Door Variables
@onready var door1: = $"../BossDoors/MainDoor"
@onready var door2: = $"../BossDoors/MainDoor2"
@onready var boss_door_area: Area3D = $"../BossDoors/BossDoorArea"
var boss_door_area_occupied: bool = false

var upgrade_station_camera
var player_camera
var upgrade_area_occupied: bool = false
var has_red_key: bool = false
var has_blue_key: bool = false

var upgrade_scene: PackedScene = preload("res://scenes/ui/improved_upgrade_menu.tscn")
var upgrade_menu_instance : Node = null

var player_in_red_key_zone: bool = false
var player_in_blue_key_zone: bool = false
var enemies_in_red_zone: int = 0
var enemies_in_blue_zone: int = 0


func _ready() -> void:
	upgrade_station.get_node("Area3D").connect("body_entered", on_upgrade_station_body_entered)
	upgrade_station.get_node("Area3D").connect("body_exited", on_upgrade_station_body_exited)

	red_key.connect("body_entered", _on_red_key_body_entered)
	red_key.connect("body_exited", _on_red_key_body_exited)

	blue_key.connect("body_entered", _on_blue_key_body_entered)
	blue_key.connect("body_exited", _on_blue_key_body_exited)

	boss_door_area.connect("body_entered", _on_boss_door_area_body_entered)
	boss_door_area.connect("body_exited", _on_boss_door_area_body_exited)

	enter_boss_area.connect("body_entered", _on_enter_boss_area_body_entered)
	upgrade_station_camera = upgrade_station.get_node("Camera3D")
	player_camera = player.get_node("Head/Camera")


func _process(_delta):
	# Keep enemy count updated
	enemies_in_red_zone = get_enemy_count(red_key_zone)
	enemies_in_blue_zone = get_enemy_count(blue_key_zone)

	# Upgrade Station Interaction
	if Input.is_action_just_pressed("interact") and upgrade_area_occupied:
		if upgrade_menu_instance == null:
			upgrade_menu_instance = upgrade_scene.instantiate()
			hud.visible = false
			get_tree().paused = true
			get_parent().add_child(upgrade_menu_instance)
		else:
			print("Upgrade menu has already been added to the scene!")

	if Input.is_action_just_pressed("back") and upgrade_area_occupied:
		hud.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_tree().paused = false
		if is_instance_valid(upgrade_menu_instance):
			upgrade_menu_instance.queue_free()
		upgrade_menu_instance = null

	# --- Red key pickup ---
	if Input.is_action_just_pressed("interact") and player_in_red_key_zone and not has_red_key:
		if enemies_in_red_zone > 0:
			print("Can't pick up key yet! Enemies remaining:", enemies_in_red_zone)
		else:
			has_red_key = true
			Audio.play("assets/sounds/key_grab.mp3")
			hud.get_node("InGameHUD/KeysContainer/RedKey").visible = true
			if is_instance_valid(red_key):
				red_key.queue_free() 
	
	# Blue key pickup
	if Input.is_action_just_pressed("interact") and player_in_blue_key_zone and not has_blue_key:
		if enemies_in_blue_zone > 0:
			print("Can't pick up key yet! Enemies remaining:", enemies_in_blue_zone)
		else:
			has_blue_key = true
			Audio.play("assets/sounds/key_grab.mp3")
			hud.get_node("InGameHUD/KeysContainer/BlueKey").visible = true
			if is_instance_valid(blue_key):
				blue_key.queue_free()

	# Boss Door Unlocking
	if Input.is_action_just_pressed("interact") and boss_door_area_occupied:
		unlock_door()

	# Key Barrier Removal
	if enemies_in_red_zone == 0 and is_instance_valid(red_key_barrier):
		red_key_barrier.queue_free()

	if enemies_in_blue_zone == 0 and is_instance_valid(blue_key_barrier):
		blue_key_barrier.queue_free()

func _on_red_key_body_entered(body) -> void:
	if body.is_in_group("Player"):
		player_in_red_key_zone = true
		interact_box.visible = true
		if enemies_in_red_zone > 0:
			red_key.get_node("Label3D").visible = true

func _on_red_key_body_exited(body) -> void:
	if body.is_in_group("Player"):
		player_in_red_key_zone = false
		red_key.get_node("Label3D").visible = false
		interact_box.visible = false
func _on_blue_key_body_entered(body) -> void:
	if body.is_in_group("Player"):
		player_in_blue_key_zone = true
		interact_box.visible = true
		if enemies_in_blue_zone > 0:
			blue_key.get_node("Label3D").visible = true

func _on_blue_key_body_exited(body) -> void:
	if body.is_in_group("Player"):
		player_in_blue_key_zone = false
		blue_key.get_node("Label3D").visible = false
		interact_box.visible = false

func _on_boss_door_area_body_entered(body) -> void:
	if body.is_in_group("Player"):
		boss_door_area_occupied = true
		interact_box.get_node("InteractLabel").text = "Unlock Doors"
		interact_box.visible = true

func _on_boss_door_area_body_exited(body) -> void:
	if body.is_in_group("Player"):
		boss_door_area_occupied = false
		interact_box.visible = false

func unlock_door():
	if has_red_key and has_blue_key:
		boss_door_area.monitoring = false
		
		var tween = get_tree().create_tween()
		tween.tween_property(door1, "position", Vector3(20,13,72), 2)
		
		var tween2 = get_tree().create_tween()
		tween2.tween_property(door2, "position", Vector3(9,13,72), 2)

		interact_box.visible = false
		print("Boss doors unlocked!")
		hud.get_node("InGameHUD/KeysContainer/RedKey").visible = false
		hud.get_node("InGameHUD/KeysContainer/BlueKey").visible = false
		Audio.play("assets/sounds/garage_door_open.wav")
		audio_player.volume_db = -15.0
		
		raise_platforms()
	else:
		print("You need both keys to unlock the boss doors!")


func raise_platforms():
	var platform1 = $"../BossDoors/Platform"
	var platform2 = $"../BossDoors/Platform2"
	var platform3 = $"../BossDoors/Platform3"
	var platform4 = $"../BossDoors/Platform4"

	var tween1 = get_tree().create_tween()
	tween1.tween_property(platform1, "position", Vector3(14.3213, 9.50667, 74.921), 1)

	var tween2 = get_tree().create_tween()
	tween2.tween_property(platform2, "position", Vector3(14.3213, 9.50667, 78.249), 2)

	var tween3 = get_tree().create_tween()
	tween3.tween_property(platform3, "position", Vector3(14.3213, 9.50667, 81.683), 3)

	var tween4 = get_tree().create_tween()
	tween4.tween_property(platform4, "position", Vector3(14.3213, 9.50667, 85.1283), 4)

func get_enemy_count(zone: Area3D) -> int:
	var count := 0
	for body in zone.get_overlapping_bodies():
		if body.is_in_group("Enemy"):
			count += 1
	#print("Enemies in  %s:" % zone.name, count)
	return count


func on_upgrade_station_body_entered(body):
	if body.is_in_group("Player"):
		upgrade_area_occupied = true


func on_upgrade_station_body_exited(body):
	if body.is_in_group("Player"):
		upgrade_area_occupied = false

func _on_enter_boss_area_body_entered(body) -> void:
	if body.is_in_group("Player"):
		print("Player has entered the boss area!")
		audio_player.stop()
		boss_music_player.play()
