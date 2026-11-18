extends Node3D
class_name LevelBase

# Shared setup for levels built from a TrenchBroom map (FuncGodotMap).
# The map is built when the level starts (see rebuild_at_runtime) and the navigation mesh is baked here so
# enemies can path. Press Build on the FuncGodotMap in the editor only if you want to preview it in the editor.
#
# Level geometry has to sit on the Environment physics layer: bullets, blood splats, impact sparks and enemy
# line-of-sight all look for it. func_godot's definitions default to layer 1 and a Build saved into a scene
# keeps whatever layer it had at the time, so every level fixes stale geometry on load.
#
# A level's own script only needs to override _level_ready() for anything extra once the level is built.

@onready var map: FuncGodotMap = $NavigationRegion3D/FuncGodotMap
@onready var navigation: NavigationRegion3D = $NavigationRegion3D
@onready var player: Node3D = $Player


# Build the level from the .map file every time the game starts, throwing away anything baked into the scene.
# Saving in TrenchBroom and pressing play is then enough; no need to press Build first.
@export var rebuild_at_runtime := true


func _ready() -> void:
	if rebuild_at_runtime:
		for child in map.get_children():
			map.remove_child(child)
			child.queue_free()
	if map.get_child_count() == 0:
		await _build_map()
	ensure_world_collision(map)
	_move_player_to_start()
	# Always bake fresh so the nav mesh matches the current map (a mesh saved in the scene can go stale)
	_bake_navigation()
	Checkpoints.level_started(self)
	_level_ready()


# Anything a level does once it is built and the player is in place
func _level_ready() -> void:
	pass


# Builds the map and waits until every step has finished
func _build_map() -> void:
	var finished := [false]
	map.build_complete.connect(func(): finished[0] = true, CONNECT_ONE_SHOT)
	map.block_until_complete = true
	map.verify_and_build()
	while not finished[0]:
		await get_tree().process_frame


# Bakes the nav mesh from the level's static colliders (enemies and pickups are ignored)
func _bake_navigation() -> void:
	navigation.bake_navigation_mesh(false)
	if navigation.navigation_mesh.get_polygon_count() == 0:
		push_warning("%s: navigation bake produced no polygons" % name)


# Puts the player on the info_player_start entity and turns them to face its angle
func _move_player_to_start() -> void:
	var start := _find_entity("info_player_start")
	if start == null:
		return
	player.global_position = start.global_position + Vector3(0, 0.1, 0)
	player.set_facing(start.global_rotation.y)


func _find_entity(classname: String) -> Node3D:
	for node in map.find_children("entity_*_" + classname, "Node3D", true, false):
		return node as Node3D
	return null


# Moves static level bodies under `root` onto the Environment layer. Returns how many it had to fix.
func ensure_world_collision(root: Node) -> int:
	var fixed := 0
	for node in root.find_children("*", "CollisionObject3D", true, false):
		if not (node is StaticBody3D or node is AnimatableBody3D):
			continue
		var body := node as CollisionObject3D
		if body.collision_layer & PhysicsLayers.ENVIRONMENT == 0:
			body.collision_layer |= PhysicsLayers.ENVIRONMENT
			fixed += 1
	if fixed > 0:
		push_warning("%s: moved %d level bodies onto the Environment physics layer (rebuild the map to fix this at the source)." % [name, fixed])
	return fixed
