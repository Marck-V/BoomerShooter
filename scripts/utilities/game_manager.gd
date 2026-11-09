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
func hit_stop(seconds: float, time_scale: float, slow_seconds := 0.0, slow_scale := 1.0) -> void:
	if hit_stop_active:
		return
	hit_stop_active = true
	Engine.time_scale = time_scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	# Optionally eases out of the freeze through slow motion: starts at slow_scale, back to full speed over slow_seconds
	if slow_seconds > 0.0:
		Engine.time_scale = slow_scale
		var ease_out := create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ease_out.tween_property(Engine, "time_scale", 1.0, slow_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await ease_out.finished
	Engine.time_scale = 1.0
	hit_stop_active = false


func player_died():
	hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.show_death_screen()
	else:
		printerr("ERROR: No reference to HUD")


# Shows the end screen with a button back to the main menu. The title and subtitle can be changed ("" hides the subtitle)
func win(title := "You Win!", subtitle := "Thank you for \nplaying our demo :)"):
	hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.show_win_screen(title, subtitle)
	else:
		printerr("ERROR: No reference to HUD.")