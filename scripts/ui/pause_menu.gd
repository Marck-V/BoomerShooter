extends Control

@onready var resume_button: Button = $MarginContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/SettingsButton
@onready var quit_button: Button = $MarginContainer/VBoxContainer/QuitButton
@onready var settings_menu: Control = $MarginContainer/SettingsMenu
@onready var hud: Control = $"../InGameHUD"


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause") and !get_tree().paused:
		pause_game()
	elif Input.is_action_just_pressed("pause") and get_tree().paused:
		if settings_menu.visible:
			settings_menu.visible = false
		else:
			resume_game()


func pause_game():
	self.visible = true
	hud.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


func resume_game():
	self.visible = false
	hud.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false


func _on_resume_button_pressed() -> void:
	resume_game()


func _on_settings_button_pressed() -> void:
	settings_menu.visible = true


func _on_quit_button_pressed() -> void:
	resume_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
