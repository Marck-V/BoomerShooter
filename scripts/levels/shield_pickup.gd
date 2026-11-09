extends Area3D

# A TrenchBroom point entity ("shield_pickup"): the shield, floating and spinning. Walking up to it shows the interact prompt, and
# pressing interact hands the player the shield (GlobalVariables.unlock), shows a short how-to-use note, and starts the wave with the same name if there is one
# (a wave_trigger with manual = 1), so the ambush begins the moment it is taken.
# The unlock is saved with the profile, so dying afterwards keeps it; a checkpoint remembers that the pickup is gone.

const ShieldModel = preload("res://scripts/player/shield_model.gd")
const PICKUP_RADIUS := 1.6
const MODEL_SCALE := 0.9
const SPIN_SPEED := 1.4
const BOB_HEIGHT := 0.12
const BOB_SPEED := 2.0
const WINDOW_THEME: Theme = preload("res://resources/themes/Windows95.tres")
const KEY_CATCHER := preload("res://scripts/levels/window_key_catcher.gd")

@export var wave := ""
@export var unlocks := "shield"

var model: Node3D
var time := 0.0
var player_inside := false
var taken := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	add_child(shape)

	# The shield stands on its edge so its front faces sideways and turns like a coin
	var pivot := Node3D.new()
	add_child(pivot)
	model = pivot
	var shield := ShieldModel.build()
	shield.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	shield.scale = Vector3.ONE * MODEL_SCALE
	pivot.add_child(shield)

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.95, 1.0)
	light.light_energy = 3.0
	light.omni_range = 8.0
	add_child(light)


func _process(delta: float) -> void:
	if player_inside and not taken and Input.is_action_just_pressed("interact"):
		_take()
		return
	time += delta
	if model:
		model.rotate_y(delta * SPIN_SPEED)
		model.position.y = sin(time * BOB_SPEED) * BOB_HEIGHT


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and not taken:
		player_inside = true
		InteractPrompt.show_prompt(get_tree(), "Take the shield")


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_inside = false
		InteractPrompt.hide_prompt(get_tree())


func _take() -> void:
	taken = true
	player_inside = false
	InteractPrompt.hide_prompt(get_tree())
	set_deferred("monitoring", false)
	GlobalVariables.unlock(unlocks)
	Audio.play("assets/audio/sfx/pickups/key_grab.mp3")
	Checkpoints.mark_gone(self)
	_show_window()
	if not wave.is_empty():
		for trigger in get_tree().current_scene.find_children("*", "Area3D", true, false):
			if trigger.has_method("start") and "wave" in trigger and trigger.wave == wave:
				trigger.start()
	model.visible = false
	for child in get_children():
		if child is OmniLight3D:
			child.visible = false


# Pauses the game and explains the shield in a window; Continue (or Enter, or Esc) closes it and the game carries on
func _show_window() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.06, 0.65)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(centre)

	var panel := PanelContainer.new()
	panel.theme = WINDOW_THEME
	panel.custom_minimum_size = Vector2(760, 0)
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "The Shield"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var entries := [
		["Parry", "%s" % NoteBox.key("parry"),
			"Press it just as an enemy shot or blow is about to land. A parry throws projectiles straight back at the enemies, and each parry freezes the moment for an instant."],
		["Block", "hold %s" % NoteBox.key("parry"),
			"Keep holding after the parry window closes and the shield stays up, taking the hits for you."],
		["Throw", NoteBox.key("throw_shield"),
			"Hurls the shield. It bounces between up to four enemies, hitting each, then flies back to you. Press %s or %s again to call it back early." % [NoteBox.key("throw_shield"), NoteBox.key("parry")]],
		["Grapple", "throw at a green point",
			"The shield sticks to a glowing green grapple point and pulls you across to it. It also refreshes your jumps and dash, so you can chain them."],
	]
	for entry in entries:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		column.add_child(row)
		var heading := Label.new()
		heading.text = "%s   (%s)" % [entry[0], entry[1]]
		heading.add_theme_font_size_override("font_size", 24)
		heading.add_theme_color_override("font_color", Color(0.1, 0.45, 0.5))
		row.add_child(heading)
		var body := Label.new()
		body.text = entry[2]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 18)
		row.add_child(body)

	var button := Button.new()
	button.text = "Continue"
	button.custom_minimum_size = Vector2(160, 40)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 22)
	column.add_child(button)

	var close := func() -> void:
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		layer.queue_free()
		queue_free()
	button.pressed.connect(close)
	var keys := Node.new()
	keys.set_script(KEY_CATCHER)
	keys.set_meta("close", close)
	layer.add_child(keys)

	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	button.grab_focus()
