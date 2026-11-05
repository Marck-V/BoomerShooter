extends "res://scripts/levels/locked_door.gd"

# A TrenchBroom brush entity ("key_door"): stays shut until the player walks up to it holding the matching key.

const LevelKey = preload("res://scripts/levels/level_key.gd")
const SENSE_RADIUS := 4.5
const LOCKED_SOUND := "assets/audio/sfx/weapons/empty_gun.mp3"

@export var key := "red"

var label: Label3D


func _setup() -> void:
	super()
	var color: Color = LevelKey.COLORS.get(key, Color.WHITE)

	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tint.albedo_color = Color(color, 0.55)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = tint

	label = Label3D.new()
	label.text = key.to_upper() + " KEY"
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.01
	label.no_depth_test = true          # it sits at the door's centre, inside the door's mesh
	label.visibility_range_end = 25.0   # and without a depth test it would otherwise show through walls from anywhere
	add_child(label)

	var sensor := Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = PhysicsLayers.PLAYER
	sensor.body_entered.connect(_on_sensor_body_entered)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SENSE_RADIUS
	shape.shape = sphere
	sensor.add_child(shape)
	add_child(sensor)


func _on_sensor_body_entered(body: Node3D) -> void:
	if is_open or not body.is_in_group("Player") or not body.has_method("has_key"):
		return
	if body.has_key(key):
		label.visible = false
		unlock()
	else:
		Audio.play(LOCKED_SOUND)
