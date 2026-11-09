extends CanvasLayer

@onready var settings_panel : Control = $SettingsMenu
@onready var back_button: Button = $SettingsMenu/SettingsPanel/BackButton


const RESET_CONFIRM_TIME := 3.0   # seconds the second click on Reset Story stays valid
var reset_armed := false


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_play_button_pressed():
	GlobalVariables.set_profile(GlobalVariables.STORY)   # the intended run: only what the story has handed out so far
	get_tree().change_scene_to_file("res://scenes/levels/level_01.tscn")

func _on_settings_button_pressed():
	settings_panel.visible = true

# Wipes the story save (pistol only, no points, no upgrades, no checkpoint). Needs a second click within a few seconds.
func _on_reset_button_pressed():
	var button: Button = $ButtonsContainer/ResetButton
	if not reset_armed:
		reset_armed = true
		button.text = "Click to confirm"
		await get_tree().create_timer(RESET_CONFIRM_TIME).timeout
		if reset_armed:
			reset_armed = false
			button.text = "Reset Story"
		return
	reset_armed = false
	GlobalVariables.reset_story()
	button.text = "Story reset"
	await get_tree().create_timer(1.5).timeout
	button.text = "Reset Story"

func _on_quit_button_pressed():
	get_tree().quit()
