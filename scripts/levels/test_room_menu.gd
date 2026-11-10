extends CanvasLayer

# The test room's menu (F1): everything the room can do, as buttons and on/off switches, instead of a hotkey each.
# It pauses the game while it's open, like the pause menu, and F1 or Esc closes it.
#
# To add something, add a line to _actions() (a button) or _switches() (an on/off switch). Every enemy in the room's
# `spawnable` list gets a spawn button by itself.

const THEME: Theme = preload("res://resources/VaporwaveTheme.tres")
const COLUMNS := 4
const BUTTON_FONT_SIZE := 22
const ACCENT := Color(1.0, 0.25, 0.75)       # synthwave pink: button borders, a switch that's on
const ACCENT_HOVER := Color(0.3, 0.9, 1.0)   # cyan
const BUTTON_FILL := Color(0.12, 0.04, 0.2, 0.9)
const SWITCH_SIZE := Vector2i(52, 28)

var room: Node                       # the test room (scripts/levels/test_room.gd)
var _panel: Control
var _switch_nodes: Array[CheckButton] = []


# Buttons below the spawn buttons: [label, what pressing it does]
func _actions() -> Array:
	return [
		["Melee dodger horde", func(): room.spawn_horde()],
		["Barrier arena", func(): room.spawn_barrier_arena()],
		["Clear enemies", func(): room.clear_enemies()],
		["Reset props", func(): room.reset_props()],
	]


# On/off switches: [label, reads whether it's on, sets it]
func _switches() -> Array:
	return [
		["Freeze enemies", func(): return room.frozen, func(on: bool): room.set_frozen(on)],
		["Shielded spawns", func(): return room.spawn_shielded, func(on: bool): room.set_spawn_shielded(on)],
		["Story profile", func(): return GlobalVariables.profile == GlobalVariables.STORY,
				func(on: bool): GlobalVariables.set_profile(GlobalVariables.STORY if on else GlobalVariables.DEV)],
	]


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS   # works while the game is paused
	_build()
	_panel.visible = false


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	for i in _switch_nodes.size():   # in case something changed them from code
		_switch_nodes[i].set_pressed_no_signal(_switches()[i][1].call())
	_panel.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close() -> void:
	_panel.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# Unhandled, so it comes after any open UI; while open it also takes Escape, so the pause menu doesn't
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F1:
		if is_open():
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = Control.new()
	_panel.theme = THEME
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.0, 0.08, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(centre)

	var box := PanelContainer.new()
	centre.add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "TEST ROOM"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(_heading("Spawn"))
	var spawns := GridContainer.new()
	spawns.columns = COLUMNS
	spawns.add_theme_constant_override("h_separation", 10)
	spawns.add_theme_constant_override("v_separation", 10)
	column.add_child(spawns)
	for scene: PackedScene in room.spawnable:
		spawns.add_child(_button(_enemy_name(scene), func(): room.spawn(scene)))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	for action in _actions():
		actions.add_child(_button(action[0], action[1]))

	column.add_child(_heading("Options"))
	var switches := GridContainer.new()
	switches.columns = 2
	switches.add_theme_constant_override("h_separation", 30)
	column.add_child(switches)
	var switch_on := _switch_texture(true)
	var switch_off := _switch_texture(false)
	for entry in _switches():
		var switch := CheckButton.new()
		switch.text = entry[0]
		switch.focus_mode = Control.FOCUS_NONE
		switch.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		switch.add_theme_icon_override("checked", switch_on)
		switch.add_theme_icon_override("unchecked", switch_off)
		switch.add_theme_constant_override("h_separation", 12)
		switch.button_pressed = entry[1].call()
		switch.toggled.connect(entry[2])
		switches.add_child(switch)
		_switch_nodes.append(switch)

	var hint := Label.new()
	hint.text = "F1 or Esc to close. Spawns appear in front of you when you close the menu."
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 20)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 46)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.add_theme_stylebox_override("normal", _button_style(ACCENT * Color(1, 1, 1, 0.7), BUTTON_FILL))
	button.add_theme_stylebox_override("hover", _button_style(ACCENT_HOVER, BUTTON_FILL.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _button_style(ACCENT_HOVER, ACCENT * Color(1, 1, 1, 0.35)))
	button.add_theme_color_override("font_hover_color", ACCENT_HOVER)
	button.pressed.connect(pressed)
	return button


func _button_style(border: Color, fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


# An on/off switch drawn into a texture: a rounded track with a round knob, pink with the knob on the right when on,
# dark with the knob on the left when off.
func _switch_texture(on: bool) -> ImageTexture:
	var w := SWITCH_SIZE.x
	var h := SWITCH_SIZE.y
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var radius := h / 2.0
	var track := ACCENT if on else Color(0.25, 0.2, 0.32)
	var knob_centre := Vector2(w - radius if on else radius, radius)
	var knob_radius := radius - 4.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# distance outside the pill: from the segment between the two end circles' centres
			var nearest := Vector2(clampf(p.x, radius, w - radius), radius)
			var track_cover := clampf(radius - p.distance_to(nearest) + 0.5, 0.0, 1.0)
			var knob_cover := clampf(knob_radius - p.distance_to(knob_centre) + 0.5, 0.0, 1.0)
			var colour := track
			colour.a = track_cover
			colour = colour.lerp(Color(1, 1, 1, track_cover), knob_cover)
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)


# "res://scenes/enemies/enemy_melee_dodger.tscn" -> "Melee Dodger"
func _enemy_name(scene: PackedScene) -> String:
	return scene.resource_path.get_file().get_basename().trim_prefix("enemy_").capitalize()
