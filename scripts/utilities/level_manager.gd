extends Node

@onready var upgrade_station: Node3D = $"../UpgradeStation"
@onready var player: CharacterBody3D = $"../Player"
@onready var hud = $"../HUD"
@onready var red_key_zone: Area3D = $"../KeyCheckAreas/RedKeyZone"
@onready var blue_key_zone: Area3D = $"../KeyCheckAreas/BlueKeyZone"
@onready var red_key: Node3D = $"../RedKeyArea"
@onready var blue_key: Node3D = $"../BlueKeyArea"
@onready var red_key_barrier = $"../RedKeyArea/Barrier"
@onready var blue_key_barrier = $"../BlueKeyArea/Barrier"

var upgrade_station_camera
var player_camera
var upgrade_area_occupied: bool = false
var has__red_key: bool = false
var has_blue_key: bool = false
var door2_unlocked: bool = false

var upgrade_scene: PackedScene = preload("res://scenes/ui/upgrade_menu.tscn")
var upgrade_menu_instance : Node = null

var player_in_red_key_zone: bool = false
var enemies_in_red_zone: int = 0
var enemies_in_blue_zone: int = 0

func _ready() -> void:
	upgrade_station.get_node("Area3D").connect("body_entered", on_upgrade_station_body_entered)
	upgrade_station.get_node("Area3D").connect("body_exited", on_upgrade_station_body_exited)

	red_key.connect("body_entered", _on_red_key_body_entered)
	red_key.connect("body_exited", _on_red_key_body_exited)
	blue_key.connect("body_entered", _on_blue_key_body_entered)
	blue_key.connect("body_exited", _on_blue_key_body_exited)

	upgrade_station_camera = upgrade_station.get_node("Camera3D")
	player_camera = player.get_node("Head/Camera")


func _process(_delta):
	# keep enemy count updated
	enemies_in_red_zone = get_enemy_count(red_key_zone)
	enemies_in_blue_zone = get_enemy_count(blue_key_zone)
	
	# --- Upgrade station ---
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
	if Input.is_action_just_pressed("interact") and player_in_red_key_zone and not has__red_key:
		if enemies_in_red_zone > 0:
			print("Can't pick up key yet! Enemies remaining:", enemies_in_red_zone)
		else:
			has__red_key = true
			print("Red key picked up!")
			if is_instance_valid(red_key):
				red_key.queue_free()

	# Blue key pickup (similar logic can be added here)
	if Input.is_action_just_pressed("interact") and not has_blue_key:
		if enemies_in_blue_zone > 0:
			print("Can't pick up blue key yet! Enemies remaining:", enemies_in_blue_zone)
		else:
			has_blue_key = true
			print("Blue key picked up!")
			if is_instance_valid(blue_key):
				blue_key.queue_free()

	# Key Barrier Removal
	if enemies_in_red_zone == 0 and is_instance_valid(red_key_barrier):
		red_key_barrier.queue_free()
	
	if enemies_in_blue_zone == 0 and is_instance_valid(blue_key_barrier):
		blue_key_barrier.queue_free()


func _on_red_key_body_entered(body) -> void:
	if body.is_in_group("Player"):
		player_in_red_key_zone = true
		hud.get_node("InGameHUD/InteractLabel").visible = true
		if enemies_in_red_zone > 0:
			red_key.get_node("Label3D").visible = true
		

func _on_red_key_body_exited(body) -> void:
	if body.is_in_group("Player"):
		player_in_red_key_zone = false
		red_key.get_node("Label3D").visible = false
		hud.get_node("InGameHUD/InteractLabel").visible = false


func _on_blue_key_body_entered(body) -> void:
	if body.is_in_group("Player"):
		hud.get_node("InGameHUD/InteractLabel").visible = true
		if enemies_in_blue_zone > 0:
			blue_key.get_node("Label3D").visible = true

func _on_blue_key_body_exited(body) -> void:
	if body.is_in_group("Player"):
		blue_key.get_node("Label3D").visible = false
		hud.get_node("InGameHUD/InteractLabel").visible = false

func unlock_door():
	pass # Placeholder for door unlock logic



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
