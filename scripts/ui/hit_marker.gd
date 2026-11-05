extends Control

# Crosshair tick confirming the player's hits: white for a body hit, yellow for a headshot, a bigger red one for a kill.
# Added to the HUD in code. Hits landing together (shotgun pellets) share one tick and sound.

const HIT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/impacts/Bullet Impact A.wav"),
	preload("res://assets/audio/sfx/impacts/Bullet Impact B.wav"),
	preload("res://assets/audio/sfx/impacts/Bullet Impact C.wav"),
	preload("res://assets/audio/sfx/impacts/Bullet Impact D.wav"),
	preload("res://assets/audio/sfx/impacts/Bullet Impact E.wav"),
]
const HIT_COLOR := Color(1.0, 1.0, 1.0)
const HEADSHOT_COLOR := Color(1.0, 0.85, 0.15)
const KILL_COLOR := Color(1.0, 0.2, 0.15)
const SHOW_TIME := 0.18
const KILL_SHOW_TIME := 0.32
const GAP := 9.0               # empty space around the crosshair's centre
const LINE_LENGTH := 9.0
const KILL_LINE_LENGTH := 15.0
const LINE_WIDTH := 2.5
const SOUND_MIN_GAP_MSEC := 50
const HIT_VOLUME_DB := -4.0

var color := HIT_COLOR
var line_length := LINE_LENGTH
var tween: Tween
var sound: AudioStreamPlayer
var last_sound_index := -1
var last_sound_msec := -1000
var kill_shown_frame := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	sound = AudioStreamPlayer.new()
	sound.bus = &"SFX"
	sound.volume_db = HIT_VOLUME_DB
	add_child(sound)
	GlobalVariables.enemy_hit.connect(_on_enemy_hit)


func _on_enemy_hit(_enemy: Node3D, headshot: bool, killed: bool) -> void:
	# A kill wins over the other pellets of the same shot
	var frame := Engine.get_process_frames()
	if not killed and kill_shown_frame == frame:
		return
	if killed:
		kill_shown_frame = frame

	color = KILL_COLOR if killed else (HEADSHOT_COLOR if headshot else HIT_COLOR)
	line_length = KILL_LINE_LENGTH if killed else LINE_LENGTH
	queue_redraw()
	modulate.a = 1.0
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, KILL_SHOW_TIME if killed else SHOW_TIME)
	_play_sound(killed)


# A random impact, never the same one twice in a row. A kill always gets through the gap between sounds.
func _play_sound(killed: bool) -> void:
	var now := Time.get_ticks_msec()
	if not killed and now - last_sound_msec < SOUND_MIN_GAP_MSEC:
		return
	last_sound_msec = now
	var index := randi_range(0, HIT_SOUNDS.size() - 1)
	if index == last_sound_index:
		index = (index + 1) % HIT_SOUNDS.size()
	last_sound_index = index
	sound.stream = HIT_SOUNDS[index]
	sound.pitch_scale = randf_range(0.95, 1.05)
	sound.play()


func _draw() -> void:
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			var direction := Vector2(x_sign, y_sign).normalized()
			draw_line(direction * GAP, direction * (GAP + line_length), color, LINE_WIDTH, true)
