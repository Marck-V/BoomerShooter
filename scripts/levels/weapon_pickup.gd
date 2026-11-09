extends Area3D
class_name WeaponPickup

# A weapon on a podium. The podium rises out of the floor, the weapon floats and spins above it, and the player takes it
# by pressing interact next to it: that hands it over (GlobalVariables.unlock), shows a note, and fires `taken`. Built in code:
#   WeaponPickup.spawn(tree, floor_position, "shotgun", "res://models/weapons/Shotgun.glb")

signal taken

const PODIUM_SIZE := Vector3(1.8, 1.1, 1.8)
const RISE_TIME := 1.4
const MODEL_LENGTH := 1.5             # the weapon is scaled to this long
const HOVER_HEIGHT := 0.9             # above the podium's top
const SPIN_SPEED := 1.3
const BOB_HEIGHT := 0.1
const PICKUP_RADIUS := 1.8
const NOTE_TIME := 8.0

var weapon_id := "shotgun"
var model_path := ""
var podium: StaticBody3D
var display: Node3D
var light: OmniLight3D
var ready_to_take := false
var player_inside := false
var time := 0.0


static func spawn(tree: SceneTree, floor_position: Vector3, id: String, model: String) -> WeaponPickup:
	var pickup := WeaponPickup.new()
	pickup.weapon_id = id
	pickup.model_path = model
	tree.current_scene.add_child(pickup)
	pickup.global_position = floor_position
	return pickup


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitoring = false   # switched on when the podium has risen
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	shape.position.y = PODIUM_SIZE.y + HOVER_HEIGHT
	add_child(shape)

	# The podium: a dark block with a glowing cap, standing on the floor (a solid for the player to walk around)
	podium = StaticBody3D.new()
	podium.collision_layer = PhysicsLayers.ENVIRONMENT
	podium.collision_mask = 0
	add_child(podium)
	var body_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = PODIUM_SIZE
	body_shape.shape = box_shape
	body_shape.position.y = PODIUM_SIZE.y * 0.5
	podium.add_child(body_shape)
	var block := MeshInstance3D.new()
	var block_mesh := BoxMesh.new()
	block_mesh.size = PODIUM_SIZE
	block.mesh = block_mesh
	block.position.y = PODIUM_SIZE.y * 0.5
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.08, 0.07, 0.12)
	stone.metallic = 0.6
	stone.roughness = 0.5
	block.material_override = stone
	podium.add_child(block)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(PODIUM_SIZE.x + 0.16, 0.1, PODIUM_SIZE.z + 0.16)
	cap.mesh = cap_mesh
	cap.position.y = PODIUM_SIZE.y
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.4, 1.8, 2.2)
	cap.material_override = glow
	podium.add_child(cap)

	# The weapon, scaled to a sensible size whatever the model's own units are
	display = Node3D.new()
	display.position.y = PODIUM_SIZE.y + HOVER_HEIGHT
	display.visible = false
	add_child(display)
	var scene := load(model_path) as PackedScene
	if scene:
		var model := scene.instantiate() as Node3D
		display.add_child(model)
		var box := _bounds(model)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if longest > 0.001:
			model.scale = Vector3.ONE * (MODEL_LENGTH / longest)
			model.position = -box.get_center() * model.scale.x   # centred on the spin
	light = OmniLight3D.new()
	light.light_color = Color(0.5, 0.95, 1.0)
	light.light_energy = 0.0
	light.omni_range = 9.0
	light.position.y = PODIUM_SIZE.y + HOVER_HEIGHT
	add_child(light)

	# Rises out of the floor, then the weapon appears and can be taken
	podium.position.y = -PODIUM_SIZE.y - 0.3
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(podium, "position:y", 0.0, RISE_TIME)
	tween.tween_callback(func() -> void:
		display.visible = true
		ready_to_take = true
		monitoring = true)
	tween.tween_property(light, "light_energy", 3.0, 0.5)
	Audio.play_at(global_position, "assets/audio/sfx/environment/garage_door_open.wav")


func _process(delta: float) -> void:
	if player_inside and ready_to_take and Input.is_action_just_pressed("interact"):
		_take()
		return
	time += delta
	if display and display.visible:
		display.rotate_y(delta * SPIN_SPEED)
		display.position.y = PODIUM_SIZE.y + HOVER_HEIGHT + sin(time * 2.0) * BOB_HEIGHT


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and ready_to_take:
		player_inside = true
		InteractPrompt.show_prompt(get_tree(), "Take the %s" % weapon_id)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_inside = false
		InteractPrompt.hide_prompt(get_tree())


func _take() -> void:
	ready_to_take = false
	player_inside = false
	InteractPrompt.hide_prompt(get_tree())
	set_deferred("monitoring", false)
	GlobalVariables.unlock(weapon_id)
	Audio.play("assets/audio/sfx/pickups/key_grab.mp3")
	display.visible = false
	light.visible = false
	var slot := {"pistol": "weapon_1", "shotgun": "weapon_2", "rifle": "weapon_3", "flamethrower": "weapon_4", "lightning": "weapon_5"}
	var lines: Array = []
	if slot.has(weapon_id):
		lines.append("Press %s to equip it." % NoteBox.key(slot[weapon_id]))
	NoteBox.show_note(get_tree(), "%s ACQUIRED" % weapon_id.to_upper(), lines, NOTE_TIME)
	taken.emit()


# The combined size of every mesh under the node, in the node's own space
func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var local := root.global_transform.affine_inverse() * mesh_node.global_transform if root.is_inside_tree() else mesh_node.transform
		var box := local * mesh_node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
