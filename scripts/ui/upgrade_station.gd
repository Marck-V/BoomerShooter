extends Node3D

# The computer the player opens the upgrade menu at. Self-contained, so dropping the scene into a level is enough.

const UPGRADE_MENU: PackedScene = preload("res://scenes/ui/improved_upgrade_menu.tscn")

var player_inside := false


func _ready() -> void:
	$Area3D.body_entered.connect(_on_body_entered)
	$Area3D.body_exited.connect(_on_body_exited)


# Pausing stops this node, and the menu frees itself when closed, so it can't be opened twice
func _process(_delta: float) -> void:
	if player_inside and Input.is_action_just_pressed("interact"):
		_open_menu()


func _open_menu() -> void:
	var scene := get_tree().current_scene
	var hud := scene.get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = false  # the HUD shows itself again on exit_upgrade_menu
	get_tree().paused = true
	scene.add_child(UPGRADE_MENU.instantiate())


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_inside = false
