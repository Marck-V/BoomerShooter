extends Area3D

# A TrenchBroom point entity ("level_key"): a floating coloured key the player collects by walking through it.
# The player holds on to it until the level reloads, and the key_door of the same colour opens for them.

const KEY_SCENE: PackedScene = preload("res://scenes/pickups/key.tscn")
const COLORS := {"red": Color(1.0, 0.15, 0.1), "blue": Color(0.15, 0.4, 1.0)}
const PICKUP_RADIUS := 1.4
const MODEL_SCALE := 0.45
const SPIN_SPEED := 1.5

@export var key := "red"

var model: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	add_child(shape)
	# The map build sets the properties right after adding the node
	_build_visuals.call_deferred()


func _build_visuals() -> void:
	var color: Color = COLORS.get(key, Color.WHITE)

	# Only the key's mesh is wanted from the scene, not its barrier and label
	var key_scene := KEY_SCENE.instantiate()
	model = key_scene.get_node("Key").duplicate() as Node3D
	key_scene.free()
	model.scale = Vector3.ONE * MODEL_SCALE
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tint.albedo_color = Color(color, 0.8)
	(model as MeshInstance3D).material_overlay = tint
	add_child(model)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 7.0
	add_child(light)


func _process(delta: float) -> void:
	if model:
		model.rotate_y(delta * SPIN_SPEED)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and body.has_method("add_key"):
		body.add_key(key)
		Audio.play("assets/sounds/key_grab.mp3")
		queue_free()
