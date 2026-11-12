extends CanvasLayer
class_name ControlsHint

# A small window at the bottom middle of the screen with the basic controls, drawn with the key pictures from
# assets/images/Input_Prompts. It never pauses the game and never takes input: it is just there while the player gets
# going, and it goes away by itself once they leave the spot they started on.
#
#   ControlsHint.show_at_start(level, player)
#
# The keys shown come from the input map (the first key or mouse button bound to each action), so changing a binding in
# the project settings changes the picture. A binding with no picture in the folder is shown as text instead.
#
# "Leaving" is dropping off the platform the level starts on (the player falls DROP_TO_CLOSE below where they spawned)
# or, on flat ground, walking CLOSE_DISTANCE away: it is judged from where the player was when the window opened, so it
# doesn't depend on any particular map.

const WINDOW_THEME: Theme = preload("res://resources/themes/Windows95.tres")
const PROMPTS := "res://assets/images/Input_Prompts/Keyboard & Mouse/Double/"
const KEY_SIZE := 38.0
const KEY_BACKING := Color.BLACK   # what shows through the transparent letters of a key picture, so they stand out
const KEY_BACKING_INSET := 2.0    # pixels in from the key's own edge, so the backing is entirely hidden behind the key
const DROP_TO_CLOSE := 2.5      # meters below the starting height
const CLOSE_DISTANCE := 20.0    # meters from the starting spot, sideways
const FADE_IN := 0.5
const FADE_OUT := 0.4
const BOTTOM_MARGIN := 28.0

# The groups shown, left to right: the actions whose keys are pictured, and what they do
const GROUPS := [
	{"actions": ["move_forward", "move_left", "move_back", "move_right"], "text": "Move"},
	{"actions": ["jump"], "text": "Jump (twice in the air)"},
	{"actions": ["dash"], "text": "Dash"},
	{"actions": ["slide"], "text": "Slam/Slide"},
	{"actions": ["shoot"], "text": "Shoot"},
]

var player: Node3D
var start_position := Vector3.ZERO
var window: PanelContainer
var closing := false


# Opens the window over `level` for a player that has just spawned
static func show_at_start(level: Node, spawned_player: Node3D) -> ControlsHint:
	var hint := ControlsHint.new()
	hint.player = spawned_player
	hint.start_position = spawned_player.global_position
	level.add_child(hint)
	return hint


func _ready() -> void:
	layer = 15
	window = PanelContainer.new()
	window.theme = WINDOW_THEME
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	window.grow_vertical = Control.GROW_DIRECTION_BEGIN
	window.offset_bottom = -BOTTOM_MARGIN
	add_child(window)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_theme_constant_override("margin_top", 0)   # the title sits in the panel's own blue title bar
	window.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.custom_minimum_size = Vector2(0, 20)
	title.position.y = -6.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 22)
	column.add_child(row)
	for group in GROUPS:
		row.add_child(_build_group(group["actions"], group["text"]))

	window.modulate.a = 0.0
	create_tween().tween_property(window, "modulate:a", 1.0, FADE_IN)


func _process(_delta: float) -> void:
	if closing or not is_instance_valid(player):
		return
	var offset := player.global_position - start_position
	if -offset.y > DROP_TO_CLOSE or Vector2(offset.x, offset.z).length() > CLOSE_DISTANCE:
		close()


# Fades the window out and removes it
func close() -> void:
	if closing:
		return
	closing = true
	var tween := create_tween()
	tween.tween_property(window, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(queue_free)


# One group: the pictures of its keys in a row, with what they do underneath
func _build_group(actions: Array, text: String) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)

	var keys := HBoxContainer.new()
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 5)
	box.add_child(keys)
	for action in actions:
		keys.add_child(key_icon(action))

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box


# The picture of the key bound to an action, or its name as text when there is no picture for it. Also used by other
# windows that name a key (the shield's), so they show the same pictures.
static func key_icon(action: String, size := KEY_SIZE) -> Control:
	var texture := key_texture(action)
	if texture == null:
		var fallback := Label.new()
		fallback.text = NoteBox.key(action)
		fallback.add_theme_font_size_override("font_size", 16)
		fallback.add_theme_color_override("font_color", Color.BLACK)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return fallback
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The key's cap only fills the middle of its picture (and wide keys are shorter), so the backing is sized from the
	# picture's own opaque area. Mouse pictures have nothing transparent to show it through and get none.
	if not texture.resource_path.get_file().begins_with("mouse"):
		var scale := size / maxf(texture.get_width(), texture.get_height())
		var cap := Rect2(texture.get_image().get_used_rect())
		var backing := Panel.new()
		var square := StyleBoxFlat.new()
		square.bg_color = KEY_BACKING
		backing.add_theme_stylebox_override("panel", square)
		backing.position = cap.position * scale + Vector2.ONE * KEY_BACKING_INSET
		backing.size = cap.size * scale - Vector2.ONE * KEY_BACKING_INSET * 2.0
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(backing)

	var icon := TextureRect.new()
	icon.texture = texture
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	return holder


# The picture for the first key or mouse button bound to an action (null if none has one)
static func key_texture(action: String) -> Texture2D:
	for event in InputMap.action_get_events(action):
		var picture := ""
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			picture = _key_picture(code)
		elif event is InputEventMouseButton:
			picture = {MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right"}.get(event.button_index, "")
		if picture.is_empty():
			continue
		var path: String = PROMPTS + picture + ".png"
		if ResourceLoader.exists(path):
			return load(path)
	return null


static func _key_picture(code: int) -> String:
	if code >= KEY_A and code <= KEY_Z:
		return "keyboard_" + char(code).to_lower()
	if code >= KEY_0 and code <= KEY_9:
		return "keyboard_" + char(code)
	match code:
		KEY_SPACE:
			return "keyboard_space"
		KEY_SHIFT:
			return "keyboard_shift"
		KEY_CTRL:
			return "keyboard_ctrl"
		KEY_ALT:
			return "keyboard_alt"
		KEY_TAB:
			return "keyboard_tab"
		KEY_ESCAPE:
			return "keyboard_escape"
		KEY_ENTER:
			return "keyboard_enter"
	return ""
