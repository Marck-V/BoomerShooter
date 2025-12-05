extends Control

@onready var hud: Control = $"../InGameHUD"


func show_win_screen():
	hud.visible = false
	visible = true
	modulate.a = 0.0  # Start fully transparent
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Fade in animation
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Important: allows tween to run while paused
	tween.tween_property(self, "modulate:a", 1.0, 0.5)  # Fade to fully opaque over 0.5 seconds



func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")