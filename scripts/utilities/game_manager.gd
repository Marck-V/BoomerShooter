extends Node

const KILL_HIT_STOP_TIME := 0.04     # real seconds the game freezes on a kill
const KILL_HIT_STOP_SCALE := 0.05
const KILL_CAMERA_SHAKE := 0.14

var hud: CanvasLayer
var hit_stop_active := false


func _ready() -> void:
	GlobalVariables.enemy_hit.connect(_on_enemy_hit)


func _on_enemy_hit(_enemy: Node3D, _headshot: bool, killed: bool) -> void:
	if not killed:
		return
	hit_stop(KILL_HIT_STOP_TIME, KILL_HIT_STOP_SCALE)
	var player = GlobalVariables.player
	if player and is_instance_valid(player):
		player.add_camera_shake(KILL_CAMERA_SHAKE)


# Freezes the game for a moment of real time: the weight of a kill or a parry
func hit_stop(seconds: float, time_scale: float) -> void:
	if hit_stop_active:
		return
	hit_stop_active = true
	Engine.time_scale = time_scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	hit_stop_active = false


func player_died():
	hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.show_death_screen()
	else:
		printerr("ERROR: No reference to HUD")


func win():
	hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.show_win_screen()
	else:
		printerr("ERROR: No reference to HUD.")