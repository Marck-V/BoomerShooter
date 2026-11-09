extends Area3D

# A TrenchBroom point entity ("shield_pickup"): the shield, floating and spinning. Walking into it hands the player the
# shield (GlobalVariables.unlock), shows a short how-to-use note, and starts the wave with the same name if there is one
# (a wave_trigger with manual = 1), so the ambush begins the moment it is taken.
# The unlock is saved with the profile, so dying afterwards keeps it; a checkpoint remembers that the pickup is gone.

const ShieldModel = preload("res://scripts/player/shield_model.gd")
const PICKUP_RADIUS := 1.6
const MODEL_SCALE := 0.9
const SPIN_SPEED := 1.4
const BOB_HEIGHT := 0.12
const BOB_SPEED := 2.0
const NOTE_TIME := 9.0
const FADE_TIME := 1.0

@export var wave := ""
@export var unlocks := "shield"

var model: Node3D
var time := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	body_entered.connect(_on_body_entered)

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
	time += delta
	if model:
		model.rotate_y(delta * SPIN_SPEED)
		model.position.y = sin(time * BOB_SPEED) * BOB_HEIGHT


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
	set_deferred("monitoring", false)
	GlobalVariables.unlock(unlocks)
	Audio.play("assets/audio/sfx/pickups/key_grab.mp3")
	Checkpoints.mark_gone(self)
	_show_note()
	if not wave.is_empty():
		for trigger in get_tree().current_scene.find_children("*", "Area3D", true, false):
			if trigger.has_method("start") and "wave" in trigger and trigger.wave == wave:
				trigger.start()
	model.visible = false
	for child in get_children():
		if child is OmniLight3D:
			child.visible = false


# A note at the bottom of the screen that fades out by itself
func _show_note() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	get_tree().root.add_child(layer)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -90.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)

	var lines := [
		["SHIELD ACQUIRED", 34, Color(0.6, 1.0, 1.0)],
		["Hold %s to parry: block a shot just as it lands and it flies back at the enemy." % _key("parry"), 20, Color.WHITE],
		["%s throws the shield. Press it again to call it back." % _key("throw_shield"), 20, Color.WHITE],
	]
	for line in lines:
		var label := Label.new()
		label.text = line[0]
		label.add_theme_font_size_override("font_size", line[1])
		label.add_theme_color_override("font_color", line[2])
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)

	var tween := layer.create_tween()
	tween.tween_interval(NOTE_TIME)
	tween.tween_property(box, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(layer.queue_free)
	queue_free_after(NOTE_TIME + FADE_TIME + 0.5)


# This pickup is hidden, not freed, until the note is done, so the tween's layer outlives nothing important
func queue_free_after(seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(queue_free)


# The first key or button bound to an action, as text
func _key(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			return event.as_text().replace(" (Physical)", "")
	return action
