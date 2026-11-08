extends Area3D
class_name LevelPortal

# The exit of a level: a big door frame that rises out of the floor, with a doorway of streaming coloured light
# in it. Walking through takes the player to the next level, or, with no level given, to the "Game Over" screen with
# its main menu button: the way out of the last level.
# Use: LevelPortal.open_at(get_tree(), floor_position, "res://scenes/levels/level_02.tscn", face_point)
#
# Travelling fades to black, loads the level and fades back in. The ammo for every weapon carries over (see
# GlobalVariables.carry_ammo_over) and the player starts the new level at full health.

const DOOR_SHADER := "res://shaders/environment/level_portal.gdshader"

const DOOR_WIDTH := 5.6             # the opening
const DOOR_HEIGHT := 8.4
const FRAME_THICKNESS := 1.0
const FRAME_DEPTH := 1.0
const RISE_TIME := 1.3              # the frame climbs out of the floor...
const OPEN_TIME := 0.9              # ...and then the doorway opens; it can't be entered before it is open
const FADE_TIME := 0.6
const FRAME_COLOR := Color(0.05, 0.02, 0.1)
const NEON_COLOR := Color(1.0, 0.12, 0.8)
const NEON_BOOST := 3.0

@export_file("*.tscn") var next_level := ""

var rig: Node3D                      # the frame and doorway, which rise together
var door_material: ShaderMaterial
var light: OmniLight3D
var open := false
var traveling := false
var flash := 0.0


# Opens the exit on the floor at `floor_position`, facing `face_point` (where the player will be coming from)
static func open_at(tree: SceneTree, floor_position: Vector3, level_path: String, face_point := Vector3.INF) -> LevelPortal:
	var gate := LevelPortal.new()
	gate.next_level = level_path
	tree.current_scene.add_child(gate)
	gate.global_position = floor_position
	if face_point != Vector3.INF:
		var toward := face_point - floor_position
		gate.rotation.y = atan2(toward.x, toward.z)
	return gate


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_WIDTH * 0.85, DOOR_HEIGHT * 0.95, FRAME_DEPTH * 1.3)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = DOOR_HEIGHT * 0.5
	add_child(collider)

	rig = Node3D.new()
	rig.position.y = -(DOOR_HEIGHT + FRAME_THICKNESS + 0.5)
	add_child(rig)
	_build_frame()
	_build_door()

	light = OmniLight3D.new()
	light.position = Vector3(0, DOOR_HEIGHT * 0.5, 2.5)
	light.light_color = Color(1.0, 0.45, 0.8)
	light.light_energy = 0.0
	light.omni_range = 18.0
	add_child(light)

	var tween := create_tween()
	tween.tween_property(rig, "position:y", 0.0, RISE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_shake_player_camera)
	tween.tween_method(_set_door_open, 0.0, 1.0, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): open = true)
	create_tween().tween_property(light, "light_energy", 3.0, RISE_TIME + OPEN_TIME)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	flash = move_toward(flash, 0.0, delta * 2.5)
	if door_material != null:
		door_material.set_shader_parameter("flash", flash)


func _physics_process(_delta: float) -> void:
	# The player may already be standing in the doorway when it opens
	if open and not traveling:
		for body in get_overlapping_bodies():
			_on_body_entered(body)


func _shake_player_camera() -> void:
	var player = GlobalVariables.player
	if is_instance_valid(player) and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.18)


func _set_door_open(value: float) -> void:
	if door_material != null:
		door_material.set_shader_parameter("open", value)


# Two pillars and a lintel in dark metal, with neon strips along the inside edge of the doorway
func _build_frame() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = FRAME_COLOR
	metal.metallic = 0.6
	metal.roughness = 0.35
	var neon := StandardMaterial3D.new()
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon.albedo_color = NEON_COLOR * NEON_BOOST

	var half_w := DOOR_WIDTH * 0.5
	var t := FRAME_THICKNESS
	# Pillars (taller than the opening, so the lintel sits on top of them) and the lintel across the top
	_add_box(Vector3(t, DOOR_HEIGHT + t, FRAME_DEPTH), Vector3(-(half_w + t * 0.5), (DOOR_HEIGHT + t) * 0.5, 0), metal)
	_add_box(Vector3(t, DOOR_HEIGHT + t, FRAME_DEPTH), Vector3(half_w + t * 0.5, (DOOR_HEIGHT + t) * 0.5, 0), metal)
	_add_box(Vector3(DOOR_WIDTH + t * 2.0, t, FRAME_DEPTH), Vector3(0, DOOR_HEIGHT + t * 0.5, 0), metal)
	# Neon on the inside edges, and a thin outline around the outside of the front face
	var strip := 0.1
	for side in [-1.0, 1.0]:
		_add_box(Vector3(strip, DOOR_HEIGHT, strip * 1.4), Vector3(side * (half_w + strip * 0.5), DOOR_HEIGHT * 0.5, 0), neon)
		_add_box(Vector3(strip, DOOR_HEIGHT + t, strip * 1.4), Vector3(side * (half_w + t - strip * 0.5), (DOOR_HEIGHT + t) * 0.5, FRAME_DEPTH * 0.5 + 0.01), neon)
		_add_box(Vector3(strip, DOOR_HEIGHT + t, strip * 1.4), Vector3(side * (half_w + t - strip * 0.5), (DOOR_HEIGHT + t) * 0.5, -FRAME_DEPTH * 0.5 - 0.01), neon)
	_add_box(Vector3(DOOR_WIDTH, strip, strip * 1.4), Vector3(0, DOOR_HEIGHT - strip * 0.5, 0), neon)
	_add_box(Vector3(DOOR_WIDTH + t * 2.0, strip, strip * 1.4), Vector3(0, DOOR_HEIGHT + t - strip * 0.5, FRAME_DEPTH * 0.5 + 0.01), neon)
	_add_box(Vector3(DOOR_WIDTH + t * 2.0, strip, strip * 1.4), Vector3(0, DOOR_HEIGHT + t - strip * 0.5, -FRAME_DEPTH * 0.5 - 0.01), neon)


func _add_box(size: Vector3, at: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(node)


# The doorway: one quad filling the opening, showing the streaming light from either side
func _build_door() -> void:
	door_material = ShaderMaterial.new()
	door_material.shader = load(DOOR_SHADER)
	door_material.set_shader_parameter("open", 0.0)
	door_material.set_shader_parameter("aspect", DOOR_WIDTH / DOOR_HEIGHT)
	var quad := QuadMesh.new()
	quad.size = Vector2(DOOR_WIDTH, DOOR_HEIGHT)
	var door := MeshInstance3D.new()
	door.mesh = quad
	door.material_override = door_material
	door.position = Vector3(0, DOOR_HEIGHT * 0.5, 0)
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(door)


func _on_body_entered(body: Node3D) -> void:
	if not open or traveling or not body.is_in_group("Player"):
		return
	traveling = true
	flash = 2.5
	travel(get_tree(), next_level)


# Fades out, loads the level with the carry-over rules, and fades back in on the other side
static func travel(tree: SceneTree, level_path: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	tree.root.add_child(layer)

	var out := layer.create_tween().set_ignore_time_scale(true)
	out.tween_property(fade, "color:a", 1.0, FADE_TIME)
	await out.finished

	if level_path.is_empty():
		# No next level: this was the way out of the game
		GameManager.win("GAME OVER", "")
		var shown := layer.create_tween().set_ignore_time_scale(true)
		shown.tween_property(fade, "color:a", 0.0, FADE_TIME)
		shown.tween_callback(layer.queue_free)
		return

	GlobalVariables.carry_ammo_over = true
	tree.change_scene_to_file(level_path)
	await tree.scene_changed
	# New level, full health. (The player scene starts at full health already; this keeps that explicit.)
	var player = GlobalVariables.player
	if is_instance_valid(player):
		player.health = 100
		GlobalVariables.health_changed.emit(100)

	var back := layer.create_tween().set_ignore_time_scale(true)
	back.tween_property(fade, "color:a", 0.0, FADE_TIME)
	back.tween_callback(layer.queue_free)
