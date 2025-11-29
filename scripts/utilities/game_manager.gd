extends Node

#@onready var pause_menu = $PauseMenu
#
#var paused := false
#
#
#func _process(_delta):
	#if Input.is_action_just_pressed("pause"):
		#pass
#
#
#func PauseGame():
	#if paused:
		#pause_menu.hide()
		#Engine.time_scale = 1
	#else:
		#pause_menu.show()
		#Engine.time_scale = 0
	#
	#paused = !paused


func player_died():
	var hud: CanvasLayer = get_tree().get_root().get_node("Node3D/HUD")
	hud.show_death_screen()
