extends Node

var hud: CanvasLayer


func player_died():
	hud = get_tree().get_root().get_node("Node3D/HUD")
	if hud:
		hud.show_death_screen()
	else:
		printerr("ERROR: No reference to HUD")


func win():
	hud = get_tree().get_root().get_node("Node3D/HUD")
	if hud:
		hud.show_win_screen()
	else:
		printerr("ERROR: No reference to HUD.")