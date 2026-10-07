extends Control

@onready var music_volume_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/MusicVolumeLabel
@onready var sfx_volume_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/SFXVolumeLabel
@onready var sensitivity_value_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/SensitivityValueLabel

@onready var music_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/MusicSlider
@onready var sfx_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/SFXSlider
@onready var sensitivity_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/SensitivitySlider
@onready var psx_value_label: LineEdit = $SettingsPanel/HBoxContainer/VboxValues/PSXValueLabel
@onready var psx_slider: HSlider = $SettingsPanel/HBoxContainer/VBoxSliders/PSXSlider
@onready var fullscreen_check: CheckButton = $SettingsPanel/FullscreenCheckButton


func _ready():
	# Finer steps so typed values land exactly where they were entered
	music_slider.step = 0.01
	sfx_slider.step = 0.01
	psx_slider.step = 0.01

	# Initialize from the saved settings (loaded by GlobalVariables on startup)
	music_slider.value = GlobalVariables.music_volume
	sfx_slider.value = GlobalVariables.sfx_volume
	sensitivity_slider.value = GlobalVariables.mouse_sensitivity
	psx_slider.value = GlobalVariables.psx_strength
	fullscreen_check.set_pressed_no_signal(GlobalVariables.fullscreen)

	_update_music_label(music_slider.value)
	_update_sfx_label(sfx_slider.value)
	_update_sensitivity_label(sensitivity_slider.value)
	_update_psx_label(psx_slider.value)

	# Text input applies on Enter or when the box loses focus; clicking in selects everything
	for line_edit in [music_volume_label, sfx_volume_label, sensitivity_value_label, psx_value_label]:
		line_edit.select_all_on_focus = true
	music_volume_label.text_submitted.connect(_on_music_input_submitted)
	sfx_volume_label.text_submitted.connect(_on_sfx_input_submitted)
	sensitivity_value_label.text_submitted.connect(_on_sensitivity_input_submitted)
	psx_value_label.text_submitted.connect(_on_psx_input_submitted)
	music_volume_label.focus_exited.connect(func(): _on_music_input_submitted(music_volume_label.text))
	sfx_volume_label.focus_exited.connect(func(): _on_sfx_input_submitted(sfx_volume_label.text))
	sensitivity_value_label.focus_exited.connect(func(): _on_sensitivity_input_submitted(sensitivity_value_label.text))
	psx_value_label.focus_exited.connect(func(): _on_psx_input_submitted(psx_value_label.text))


# ---- SLIDER CALLBACKS ----
func _on_music_slider_value_changed(value: float):
	var db = linear_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)
	GlobalVariables.music_volume = value
	GlobalVariables.request_settings_save()
	_update_music_label(value)

func _on_sfx_slider_value_changed(value: float):
	var db = linear_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)
	GlobalVariables.sfx_volume = value
	GlobalVariables.request_settings_save()
	_update_sfx_label(value)

func _on_sensitivity_slider_value_changed(value: float):
	GlobalVariables.mouse_sensitivity = value
	GlobalVariables.request_settings_save()
	_update_sensitivity_label(value)


# ---- LINEEDIT (TEXT INPUT) CALLBACKS ----
# Accepts "50", "50%", " 50 %" etc. Returns null when the text isn't a number.
func _parse_number(text: String) -> Variant:
	var cleaned = text.replace("%", "").strip_edges()
	if not cleaned.is_valid_float():
		return null
	return cleaned.to_float()

func _on_music_input_submitted(text: String):
	var number = _parse_number(text)
	if number != null:
		music_slider.value = clampf(number / 100.0, 0.0, 1.0)  # triggers value_changed
	_update_music_label(music_slider.value)

func _on_sfx_input_submitted(text: String):
	var number = _parse_number(text)
	if number != null:
		sfx_slider.value = clampf(number / 100.0, 0.0, 1.0)
	_update_sfx_label(sfx_slider.value)

func _on_sensitivity_input_submitted(text: String):
	var number = _parse_number(text)
	if number != null:
		sensitivity_slider.value = clampf(number, sensitivity_slider.min_value, sensitivity_slider.max_value)
	_update_sensitivity_label(sensitivity_slider.value)


# ---- LABEL UPDATE HELPERS ----
func _update_music_label(value: float):
	music_volume_label.text = str(round(value * 1000) / 10.0) + "%"

func _update_sfx_label(value: float):
	sfx_volume_label.text = str(round(value * 1000) / 10.0) + "%"

func _update_sensitivity_label(value: float):
	sensitivity_value_label.text = str(round(value * 10) / 10.0)


# ---- UI Functionality ----
func _on_fullscreen_check_button_toggled(toggled_on):
	GlobalVariables.fullscreen = toggled_on
	GlobalVariables.request_settings_save()
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back_button_pressed() -> void:
	GlobalVariables.save_settings()
	self.visible = false


# ---- PSX RETRO FILTER ----
func _on_psx_slider_value_changed(value: float):
	GlobalVariables.psx_strength = value
	GlobalVariables.request_settings_save()
	if GlobalVariables.player and is_instance_valid(GlobalVariables.player):
		GlobalVariables.player.psx_material.set_shader_parameter("effect_strength", value)
	_update_psx_label(value)

func _on_psx_input_submitted(text: String):
	var number = _parse_number(text)
	if number != null:
		psx_slider.value = clampf(number / 100.0, 0.0, 1.0)
	_update_psx_label(psx_slider.value)

func _update_psx_label(value: float):
	psx_value_label.text = str(int(round(value * 100))) + "%"
