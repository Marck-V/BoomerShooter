extends Area3D

# A TrenchBroom trigger volume (entity "wave_trigger"). Enemies with the same "wave" are held out of the
# level until the player walks in here. Then the entrance doors of the wave (locked_door with starts_open = 1)
# shut, the enemies spawn in a few at a time with a flash, and once they are all dead every door of the wave opens.

const SpawnEffect = preload("res://scripts/levels/spawn_effect.gd")

@export var wave := ""
@export var manual: int = 0           # 1: walking in does nothing; something else starts the wave by calling start()
@export var spawn_interval := 0.1     # seconds between enemies appearing

var held: Array[Node] = []
var parents := {}          # held enemy -> the node it will be added back to
var remaining := {}        # enemies from this wave that have not died yet (including ones not spawned yet)
var triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Wait for the map build to finish adding every entity before collecting the wave
	for i in 3:
		await get_tree().process_frame
	_hold_wave_enemies()


func _exit_tree() -> void:
	# Enemies still waiting are not in the tree, so nothing else would free them
	for enemy in held:
		if is_instance_valid(enemy) and not enemy.is_inside_tree():
			enemy.queue_free()


func _hold_wave_enemies() -> void:
	if wave.is_empty():
		return
	# Beaten before the checkpoint the player came back to: its enemies are already gone, so just open up
	if Checkpoints.is_wave_cleared(wave):
		triggered = true
		for door in _wave_doors():
			door.open_now()
		return
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if "wave" in enemy and enemy.wave == wave:
			var parent := enemy.get_parent()
			parent.remove_child(enemy)
			held.append(enemy)
			parents[enemy] = parent


func _on_body_entered(body: Node3D) -> void:
	if manual == 1 or not body.is_in_group("Player"):
		return
	start()


# Starts the wave (once): the entrance doors shut and the enemies come in
func start() -> void:
	if triggered:
		return
	triggered = true
	GlobalVariables.enemy_died.connect(_on_enemy_died)
	for enemy in held:
		remaining[enemy] = true
	for door in _wave_doors():
		if door.starts_open == 1:
			door.lock()
	_spawn_enemies()


# Nearest to the trigger first, so the wave rolls out from the entrance
func _spawn_enemies() -> void:
	var queue := held.duplicate()
	held.clear()
	queue.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.position.distance_squared_to(position) < b.position.distance_squared_to(position))
	for enemy in queue:
		if not is_instance_valid(enemy):
			remaining.erase(enemy)
			continue
		parents[enemy].add_child(enemy)
		SpawnEffect.play(get_tree(), (enemy as Node3D).global_position)
		_alert.call_deferred(enemy)
		if spawn_interval > 0.0:
			await get_tree().create_timer(spawn_interval, false).timeout
	if remaining.is_empty():
		_wave_cleared()


# A wave comes for the player whatever the distance: enemies only notice the player inside their vision area (about
# 18 m), so one spawned further away would stand idle forever with the doors shut behind the player
func _alert(enemy: Node) -> void:
	for i in 3:
		await get_tree().process_frame
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			return
	var player := get_tree().get_first_node_in_group("Player")
	if player and enemy.has_method("_on_body_entered") and "target" in enemy and is_instance_valid(enemy.target):
		enemy.call("_on_body_entered", enemy.target)


func _on_enemy_died(enemy: Node3D) -> void:
	if remaining.erase(enemy) and remaining.is_empty() and held.is_empty():
		_wave_cleared()


func _wave_cleared() -> void:
	Checkpoints.mark_wave_cleared(wave)
	for door in _wave_doors():
		door.unlock()


# Found by walking the level (not a group), since a door's wave is only set after it enters the tree
func _wave_doors() -> Array[Node]:
	var doors: Array[Node] = []
	for node in get_tree().current_scene.find_children("*", "AnimatableBody3D", true, false):
		if node.has_method("unlock") and node.wave == wave:
			doors.append(node)
	return doors
