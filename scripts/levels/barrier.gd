extends "res://scripts/levels/locked_door.gd"

# A TrenchBroom brush entity ("barrier"): a big red holographic wall that closes off a combat area without a door, so
# the level can stay open (windows, sky, the view beyond) and still shut the player in for a fight.
#
# It works with the same "wave" name as a wave_trigger and the enemies and doors of that wave:
#   - until the wave starts it is not there at all (no wall, no collision: it does not even show in the navigation mesh)
#   - when the player walks into the trigger it is drawn up out of the floor and blocks the player and the enemies
#   - when every enemy of the wave is dead it is drawn away and they can walk through again
# Like a door it is only solid to bodies: it is on the environment layer, so shots and projectiles stop at it too.
# Draw it as a thin brush (about 0.25 m) as tall as the opening needs. Any texture: it is covered with the hologram.
# In code: Barrier.create(Vector3(width, height, 0.25)), add it, set .wave, then position it.

const SHADER: Shader = preload("res://shaders/environment/barrier_hologram.gdshader")
const RAISE_TIME := 0.55
const DROP_TIME := 0.5
const RAISE_SOUND := "assets/audio/sfx/player/shield_block.mp3"
const DROP_SOUND := "assets/audio/sfx/ui/accepter.mp3"

var material: ShaderMaterial
var meshes: Array[MeshInstance3D] = []
var reveal_tween: Tween


func _init() -> void:
	starts_open = 1   # "open" is the barrier being down: it is up only while its wave is on


# Not solid from the moment it exists: the level bakes its navigation mesh as soon as the map is built, which is before
# the deferred _setup() below runs, and a barrier that was solid then would cut a permanent hole in the mesh
func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	super()


static func create(size: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.set_script(load("res://scripts/levels/barrier.gd"))
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body


# The map build adds the brush's meshes and collision shapes and sets the properties right after adding the node
func _setup() -> void:
	starts_open = 1
	is_open = true
	collision_layer = 0   # also keeps the level's navigation bake from seeing it
	collision_mask = 0
	material = ShaderMaterial.new()
	material.shader = SHADER
	var bounds := AABB()
	var first := true
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		meshes.append(mesh)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = material
		mesh.visible = false
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	material.set_shader_parameter("y_bottom", bounds.position.y)
	material.set_shader_parameter("y_top", bounds.end.y)
	material.set_shader_parameter("reveal", 0.0)
	_rebake_navigation.call_deferred()


# The level bakes its navigation mesh right after building the map, while a barrier may still be solid (this runs a
# little later). Baked like that it would leave a permanent hole in the mesh where it stands. So once the barriers are
# all set up, the mesh is baked again, once per level, with them out of the way.
func _rebake_navigation() -> void:
	var region: NavigationRegion3D = null
	var node := get_parent()
	while node != null and region == null:
		region = node as NavigationRegion3D
		node = node.get_parent()
	if region == null or region.has_meta("barriers_rebaked"):
		return
	region.set_meta("barriers_rebaked", true)
	await get_tree().process_frame
	if is_instance_valid(region) and region.is_inside_tree():
		region.bake_navigation_mesh(true)


# The wave has started: the barrier comes up
func lock() -> void:
	if not is_open:
		return
	is_open = false
	collision_layer = PhysicsLayers.ENVIRONMENT
	_show(true)
	Audio.play_at(global_position, RAISE_SOUND)


# The wave is dead: the barrier goes. It stops blocking at once.
func unlock() -> void:
	if is_open:
		return
	is_open = true
	collision_layer = 0
	_show(false)
	Audio.play_at(global_position, DROP_SOUND)


# Down straight away with no sound, for a wave already beaten before the checkpoint the player came back to
func open_now() -> void:
	is_open = true
	collision_layer = 0
	if reveal_tween:
		reveal_tween.kill()
	if material:
		material.set_shader_parameter("reveal", 0.0)
	for mesh in meshes:
		mesh.visible = false


func _show(up: bool) -> void:
	if reveal_tween:
		reveal_tween.kill()
	if up:
		for mesh in meshes:
			mesh.visible = true
	reveal_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if up else Tween.EASE_IN)
	reveal_tween.tween_method(func(value: float) -> void: material.set_shader_parameter("reveal", value),
			material.get_shader_parameter("reveal"), 1.0 if up else 0.0, RAISE_TIME if up else DROP_TIME)
	if not up:
		reveal_tween.tween_callback(func() -> void:
			for mesh in meshes:
				mesh.visible = false)
