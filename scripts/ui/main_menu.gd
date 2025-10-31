extends CanvasLayer

@onready var settings_panel : Panel = $SettingsPanel
@onready var back_button : Button = $SettingsPanel/BackButton


func _on_play_button_pressed():
    get_tree().change_scene_to_file("res://scenes/test_scenes/brandon_enemy_test.tscn")

func _on_back_button_pressed():
    settings_panel.visible = false

func _on_settings_button_pressed():
    settings_panel.visible = true

func _on_quit_button_pressed():
    get_tree().quit()
