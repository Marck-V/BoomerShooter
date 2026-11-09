class_name NoteBox

# A short note at the bottom of the screen that fades out by itself, for hints: NoteBox.show_note(tree, "TITLE", ["line", ...])
# Key names for actions come from the input map: NoteBox.key("parry") -> "Right Mouse Button".

const DEFAULT_TIME := 7.0
const FADE_TIME := 1.0


static func show_note(tree: SceneTree, title: String, lines: Array, seconds := DEFAULT_TIME) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	tree.root.add_child(layer)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -90.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)

	_add_label(box, title, 34, Color(0.6, 1.0, 1.0))
	for line in lines:
		_add_label(box, line, 20, Color.WHITE)

	var tween := layer.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(box, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(layer.queue_free)


static func _add_label(box: Control, text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)


# The first key or button bound to an action, as text
static func key(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.as_text_physical_keycode() if event.physical_keycode != 0 else event.as_text_keycode()
		if event is InputEventMouseButton:
			return event.as_text()
	return action
