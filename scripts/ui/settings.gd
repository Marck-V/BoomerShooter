extends Panel

func _ready():
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(0.2))
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(0.2))


func _on_music_slider_value_changed(value:float):
    var db = linear_to_db(value)
    var audio_bus_id = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_volume_db(audio_bus_id, db)


func _on_sfx_slider_value_changed(value:float):
    var db = linear_to_db(value)
    var audio_bus_id = AudioServer.get_bus_index("SFX")
    AudioServer.set_bus_volume_db(audio_bus_id, db)


func _on_sensitivity_slider_value_changed(value:float):
    print("Sensitivity: ", value)


func _on_fullscreen_check_button_toggled(toggled_on):
    if  toggled_on == true:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
