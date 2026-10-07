extends Control

@onready var resume_button: Button = $MarginContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/SettingsButton
@onready var quit_button: Button = $MarginContainer/VBoxContainer/QuitButton
@onready var settings_menu: Control = $MarginContainer/SettingsMenu
@onready var hud: Control = $"../InGameHUD"


# Event-based (not polled) so another menu, like the upgrade menu, can consume Escape first
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo():
		return

	# Death and win screens also pause the game; Escape does nothing there
	for screen_name in ["DeathScreen", "WinScreen"]:
		var screen := get_node_or_null("../" + screen_name) as Control
		if screen and screen.visible:
			get_viewport().set_input_as_handled()
			return

	if !get_tree().paused:
		pause_game()
	elif settings_menu.visible:
		settings_menu.visible = false
	else:
		resume_game()
	get_viewport().set_input_as_handled()


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
