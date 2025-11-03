extends Control

@onready var music_volume_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/MusicVolumeLabel
@onready var sfx_volume_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/SFXVolumeLabel
@onready var sensitivity_value_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/SensitivityValueLabel

@onready var music_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/MusicSlider
@onready var sfx_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/SFXSlider
@onready var sensitivity_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/SensitivitySlider


func _ready():
	# Initialize defaults (or load from settings)
	music_slider.value = 0.2
	sfx_slider.value = 0.2
	sensitivity_slider.value = GlobalVariables.mouse_sensitivity

	_update_music_label(music_slider.value)
	_update_sfx_label(sfx_slider.value)
	_update_sensitivity_label(sensitivity_slider.value)

	# Apply initial volumes
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_slider.value))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_slider.value))

	# Connect text input (player manual edits)
	music_volume_label.text_submitted.connect(_on_music_input_submitted)
	sfx_volume_label.text_submitted.connect(_on_sfx_input_submitted)
	sensitivity_value_label.text_submitted.connect(_on_sensitivity_input_submitted)


# ---- SLIDER CALLBACKS ----
func _on_music_slider_value_changed(value: float):
	var db = linear_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)
	_update_music_label(value)

func _on_sfx_slider_value_changed(value: float):
	var db = linear_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)
	_update_sfx_label(value)

func _on_sensitivity_slider_value_changed(value: float):
	GlobalVariables.mouse_sensitivity = value
	_update_sensitivity_label(value)


# ---- LINEEDIT (TEXT INPUT) CALLBACKS ----
func _on_music_input_submitted(text: String):
	if not text.is_valid_float():
		_update_music_label(music_slider.value)
		return
	var cleaned_text = text.replace("%", "").strip_edges()
	var percent = clamp(float(cleaned_text) / 100.0, 0.0, 1.0)
	music_slider.value = percent  # triggers value_changed

func _on_sfx_input_submitted(text: String):
	if not text.is_valid_float():
		_update_sfx_label(sfx_slider.value)
		return
	var cleaned_text = text.replace("%", "").strip_edges()
	var percent = clamp(float(cleaned_text) / 100.0, 0.0, 1.0)
	sfx_slider.value = percent

func _on_sensitivity_input_submitted(text: String):
	if not text.is_valid_float():
		_update_sensitivity_label(sensitivity_slider.value)
		return
	var value = clamp(float(text), 100.0, 1000.0)
	sensitivity_slider.value = value
	GlobalVariables.mouse_sensitivity = value


# ---- LABEL UPDATE HELPERS ----
func _update_music_label(value: float):
	music_volume_label.text = str(round(value * 1000) / 10.0) + "%"

func _update_sfx_label(value: float):
	sfx_volume_label.text = str(round(value * 1000) / 10.0) + "%"

func _update_sensitivity_label(value: float):
	sensitivity_value_label.text = str(round(value * 10) / 10.0)


# ---- UI Functionality ----
func _on_fullscreen_check_button_toggled(toggled_on):
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back_button_pressed() -> void:
	self.visible = false
