extends Area3D

# A TrenchBroom point entity ("level_key"): a floating coloured key. Walking up to it shows the interact prompt, and
# pressing interact takes it. The player holds on to it for the rest of the level (a checkpoint remembers it), and the key_door of the same
# colour opens for them.

const KEY_SCENE: PackedScene = preload("res://scenes/pickups/key.tscn")
const COLORS := {"red": Color(1.0, 0.15, 0.1), "blue": Color(0.15, 0.4, 1.0)}
const PICKUP_RADIUS := 2.0
const MODEL_SCALE := 0.45
const SPIN_SPEED := 1.5

@export var key := "red"

var model: Node3D
var player: Node3D      # the player, while they are in reach


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
	if is_instance_valid(player) and Input.is_action_just_pressed("interact"):
		_take()
		return
	if model:
		model.rotate_y(delta * SPIN_SPEED)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and body.has_method("add_key"):
		player = body
		InteractPrompt.show_prompt(get_tree(), "Take the %s key" % key)


func _on_body_exited(body: Node3D) -> void:
	if body == player:
		player = null
		InteractPrompt.hide_prompt(get_tree())


func _take() -> void:
	InteractPrompt.hide_prompt(get_tree())
	player.add_key(key)
	player = null
	Audio.play("assets/audio/sfx/pickups/key_grab.mp3")
	Checkpoints.mark_gone(self)
	queue_free()
