extends Control


# Panels
@onready var levels_panel: Panel = $LevelsPanel
@onready var settings_panel: Panel = $SettingsPanel

func _ready():
	levels_panel.visible = false
	settings_panel.visible = false
	
func _process(_delta: float):
	pass

# Quit the game
func _on_power_button_pressed() -> void:
	get_tree().quit()

# Open the levels select panel
func _on_level_select_button_pressed() -> void:
	levels_panel.visible = true

# Close the levels select panel
func _on_close__levels_panel_button_pressed() -> void:
	levels_panel.visible = false
	
# Open the settings panel
func _on_settings_button_pressed() -> void:
	settings_panel.visible = true

# Close the settings panel
func _on_close__settings_panel_button_pressed() -> void:
	settings_panel.visible = false
