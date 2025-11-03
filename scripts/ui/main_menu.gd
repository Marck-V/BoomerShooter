extends CanvasLayer

@onready var settings_panel : Control = $SettingsMenu
@onready var back_button: Button = $SettingsMenu/SettingsPanel/BackButton


func _on_play_button_pressed():
	get_tree().change_scene_to_file("res://scenes/test_scenes/enemy_room.tscn")

func _on_settings_button_pressed():
	settings_panel.visible = true

func _on_quit_button_pressed():
	get_tree().quit()
