extends Node

var paused := false

@onready var pause_menu = $PauseMenu

func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		pass
		
func PauseGame():
	if paused:
		pause_menu.hide()
		Engine.time_scale = 1
	else:
		pause_menu.show()
		Engine.time_scale = 0
	
	paused = !paused
