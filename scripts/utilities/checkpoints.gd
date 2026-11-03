extends Node

# Where the player comes back after dying, and what the level looked like then.
#
# A snapshot (CheckpointData) is taken when a level starts and again whenever the player walks through a
# checkpoint. Dying reloads the scene and puts it back the way the snapshot recorded it: the player's points,
# ammo, upgrades, keys and weapon, and every pickup, key, enemy and wave that was already dealt with. Health
# always comes back full.
#
# Levels that build themselves when they load (LevelBase) call level_started() once they are built. Any other
# scene with a player in it is started as soon as it loads.

const SAVE_PATH := "user://checkpoint.res"
const NO_STABLE_NAME := "@"   # nodes spawned at runtime get names like "@Enemy@42" that differ every run

signal checkpoint_reached(checkpoint: Node)

var current: CheckpointData   # what dying goes back to; null outside a level

# Progress since the level started, copied into each snapshot
var _gone := {}
var _cleared_waves := {}
var _reached := {}


func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)
	GlobalVariables.enemy_died.connect(mark_gone)


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene is LevelBase:
		return   # it calls level_started() once its map is built
	if _find_player() != null:
		level_started(scene)
	else:
		clear()   # a menu: the run is over


# Starts a fresh run of the level, or carries on from the snapshot if it is for this level (after dying)
func level_started(level: Node) -> void:
	if current and current.level_path == level.scene_file_path:
		_restore(level)
		return
	_gone.clear()
	_cleared_waves.clear()
	_reached.clear()
	var player := _find_player()
	if player:
		current = _snapshot(level, "", player.global_position, player.rotation_target.y)


# Called by a checkpoint the player walks into. Each one only counts the first time: returns whether this was it.
func reach(checkpoint: Node3D, spawn_position: Vector3) -> bool:
	var level := get_tree().current_scene
	var id := String(level.get_path_to(checkpoint))
	var player := _find_player()
	if current == null or player == null or _reached.has(id):
		return false
	_reached[id] = true
	current = _snapshot(level, id, spawn_position, player.rotation_target.y)
	checkpoint_reached.emit(checkpoint)
	return true


func is_reached(checkpoint: Node) -> bool:
	return _reached.has(String(get_tree().current_scene.get_path_to(checkpoint)))


# Back to the last checkpoint (or the level start)
func respawn() -> void:
	get_tree().reload_current_scene()


func clear() -> void:
	current = null
	_gone.clear()
	_cleared_waves.clear()
	_reached.clear()


# A pickup, key or enemy from the level that has been used up, and should stay gone after a respawn
func mark_gone(node: Node) -> void:
	var level := get_tree().current_scene
	if current == null or level == null or not level.is_ancestor_of(node):
		return
	var path := String(level.get_path_to(node))
	if not path.contains(NO_STABLE_NAME):
		_gone[path] = true


func mark_wave_cleared(wave: String) -> void:
	_cleared_waves[wave] = true


func is_wave_cleared(wave: String) -> bool:
	return _cleared_waves.has(wave)


# --- Saving between sessions (nothing calls these yet) ---
# To continue a run after the game is closed: save_to_disk() when a checkpoint is reached, and on "Continue"
# call load_from_disk() and change to current.level_path. level_started() then restores it like a respawn.
func save_to_disk() -> void:
	if current:
		ResourceSaver.save(current, SAVE_PATH)


func load_from_disk() -> bool:
	if not ResourceLoader.exists(SAVE_PATH):
		return false
	current = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CheckpointData
	return current != null


func _snapshot(level: Node, id: String, spawn_position: Vector3, spawn_yaw: float) -> CheckpointData:
	var player := _find_player()
	var data := CheckpointData.new()
	data.level_path = level.scene_file_path
	data.checkpoint_id = id
	data.spawn_position = spawn_position
	data.spawn_yaw = spawn_yaw
	data.points = GlobalVariables.save_data.points
	data.ammo = GlobalVariables.save_data.ammo.duplicate()
	data.upgrades = GlobalVariables.save_data.upgrades.duplicate()
	data.keys = PackedStringArray(player.keys.keys())
	data.weapon_index = player.weapon_index
	data.gone = PackedStringArray(_gone.keys())
	data.cleared_waves = PackedStringArray(_cleared_waves.keys())
	data.reached_checkpoints = PackedStringArray(_reached.keys())
	return data


func _restore(level: Node) -> void:
	_gone.clear()
	_cleared_waves.clear()
	_reached.clear()
	for path in current.gone:
		_gone[path] = true
		var node := level.get_node_or_null(NodePath(path))
		if node:
			# Out of the tree now, so wave triggers collecting their enemies don't pick it up
			node.get_parent().remove_child(node)
			node.queue_free()
	for wave in current.cleared_waves:
		_cleared_waves[wave] = true
	for id in current.reached_checkpoints:
		_reached[id] = true

	GlobalVariables.restore_progress(current.points, current.ammo, current.upgrades)

	var player := _find_player()
	if player == null:
		return
	player.global_position = current.spawn_position + Vector3.UP * 0.1
	player.set_facing(current.spawn_yaw)
	player.reset_physics_interpolation()
	for key in current.keys:
		player.add_key(key)
	player.change_weapon(current.weapon_index, false)


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("Player") as Node3D
