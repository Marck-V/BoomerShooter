extends Node3D

# The testing grounds (scenes/test_scenes/test_room.tscn): an empty walled floor, with a platform and ramp and two
# pillars, for trying out enemies without a level getting in the way.
#
# God mode is on by default: hits still land and lower your health, but it never goes below 1 and refills once it
# drops under refill_below. Nothing is placed in the room; spawn what you want to test:
#   Alt+1..Alt+9   spawn the matching entry of `spawnable` in front of you
#   Alt+0          remove every enemy
#   Alt+F          freeze / unfreeze the enemies' AI (they stay where they are, animations pause)
#
# The same things can be done from code while the game runs (spawn(), clear_enemies(), set_frozen()), and every hit
# the player takes is logged in damage_log, so a test can measure what an attack does.

const PLAYER_MAX_HEALTH := 100

@export var god_mode := true
@export var refill_below := 30                # god mode tops health back up once it falls under this
@export var spawn_distance := 6.0
@export var spawnable: Array[PackedScene] = [
	preload("res://scenes/enemies/enemy_horde.tscn"),
	preload("res://scenes/enemies/enemy_melee_dodger.tscn"),
	preload("res://scenes/enemies/enemy_swordsman.tscn"),
	preload("res://scenes/enemies/enemy_ranged.tscn"),
	preload("res://scenes/enemies/enemy_dodger.tscn"),
	preload("res://scenes/enemies/enemy_flyer.tscn"),
	preload("res://scenes/enemies/enemy_bomber.tscn"),
	preload("res://scenes/enemies/enemy_brute.tscn"),
]

@onready var player: Node3D = $Player
@onready var navigation: NavigationRegion3D = $NavigationRegion3D
@onready var enemies: Node3D = $Enemies

var frozen := false
var damage_log: Array[Dictionary] = []   # {time, amount, health} for every hit the player takes
var _last_health := PLAYER_MAX_HEALTH


func _ready() -> void:
	navigation.bake_navigation_mesh(false)
	player.set("cannot_die", god_mode)
	_last_health = player.get("health")
	player.health_updated.connect(_on_player_health_updated)


func _on_player_health_updated(_health = null) -> void:
	var health: int = player.get("health")
	if health < _last_health:
		damage_log.append({"time": Time.get_ticks_msec() / 1000.0, "amount": _last_health - health, "health": health})
	_last_health = health
	if god_mode and health < refill_below:
		_refill.call_deferred()


func _refill() -> void:
	player.set("health", PLAYER_MAX_HEALTH)
	_last_health = PLAYER_MAX_HEALTH
	player.health_updated.emit(PLAYER_MAX_HEALTH)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.alt_pressed:
		return
	if key.keycode == KEY_0:
		clear_enemies()
	elif key.keycode == KEY_F:
		set_frozen(not frozen)
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var index := key.keycode - KEY_1
		if index < spawnable.size():
			spawn(spawnable[index])
	else:
		return
	get_viewport().set_input_as_handled()


# Spawns an enemy (a PackedScene or a res:// path) `distance` in front of where the player looks, turned
# `angle_degrees` round them (positive = to the player's right). Returns the enemy.
func spawn(what, distance := -1.0, angle_degrees := 0.0) -> Node3D:
	var scene: PackedScene = load(what) if what is String else what
	var enemy := scene.instantiate() as Node3D
	enemies.add_child(enemy)
	var forward := -get_viewport().get_camera_3d().global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	forward = forward.rotated(Vector3.UP, -deg_to_rad(angle_degrees))
	enemy.global_position = player.global_position + forward * (spawn_distance if distance < 0.0 else distance)
	var to_player := player.global_position - enemy.global_position
	to_player.y = 0.0
	if to_player.length() > 0.01:
		enemy.global_transform.basis = Basis.looking_at(to_player.normalized(), Vector3.UP).rotated(Vector3.UP, PI)
	if frozen:
		_freeze(enemy, true)
	return enemy


func clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if enemy is EnemyBase:
			enemy.queue_free()


# Stops (or restarts) every enemy where it is, animations included
func set_frozen(value: bool) -> void:
	frozen = value
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if enemy is EnemyBase:
			_freeze(enemy, value)


func _freeze(enemy: Node, value: bool) -> void:
	enemy.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
