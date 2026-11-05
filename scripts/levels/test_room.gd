extends Node3D

# The testing grounds (scenes/test_scenes/test_room.tscn): an empty walled floor, with a platform and ramp and two
# pillars, for trying out enemies without a level getting in the way.
#
# God mode is on by default: hits still land and lower your health, but it never goes below 1 and refills once it
# drops under refill_below. Ammo is unlimited too (unlimited_ammo). A grapple point hangs above the platform for
# trying the shield's grapple. No enemies are placed in the room; spawn what you want to test from the test menu
# (F1, scripts/levels/test_room_menu.gd), which pauses the game while it's open:
#   spawn buttons    one for each entry of `spawnable`, in front of you
#   Melee dodger horde   HORDE_SIZE melee dodgers in two staggered rows ahead of you
#   Clear enemies    removes every enemy
#   Freeze enemies   switch: stops the enemies' AI where they are (animations pause; they can still be hit)
#   Shielded spawns  switch: while on, every enemy spawned comes with a shield
#
# The same things can be done from code while the game runs (spawn(), spawn_horde(), clear_enemies(), set_frozen(),
# set_spawn_shielded()), and every hit the player takes is logged in damage_log, so a test can measure what an
# attack does.

const PLAYER_MAX_HEALTH := 100
const HORDE_SCENE := preload("res://scenes/enemies/enemy_melee_dodger.tscn")
const SPAWN_SPACING := 2.5                      # metres between enemies spawned from the menu
const HORDE_SIZE := 8
const HORDE_DISTANCES := [10.0, 13.0]           # metres to the front and back row
const HORDE_SPREAD := 50.0                      # degrees each row fans across

@export var god_mode := true
@export var refill_below := 30                # god mode tops health back up once it falls under this
@export var unlimited_ammo := true            # shooting costs no ammo while in the room
@export var spawn_distance := 6.0
@export var spawn_shielded := false           # enemies spawned while this is on come with a shield
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
@onready var help_label: Label = $Help/Label

var frozen := false
var damage_log: Array[Dictionary] = []   # {time, amount, health} for every hit the player takes
var menu: CanvasLayer                    # the F1 test menu
var _last_health := PLAYER_MAX_HEALTH


func _ready() -> void:
	navigation.bake_navigation_mesh(false)
	player.set("cannot_die", god_mode)
	_last_health = player.get("health")
	player.health_updated.connect(_on_player_health_updated)
	GlobalVariables.infinite_ammo = unlimited_ammo
	menu = preload("res://scripts/levels/test_room_menu.gd").new()
	menu.room = self
	add_child(menu)
	_update_help()


# Leaving the room (to the menu or a level) puts ammo back to normal
func _exit_tree() -> void:
	GlobalVariables.infinite_ammo = false


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


# Spawns an enemy (a PackedScene or a res:// path) `distance` in front of where the player looks, turned
# `angle_degrees` round them (positive = to the player's right). It has a shield if shielded spawns are on, or if
# `shielded` says so (-1 follows the toggle, 0 never, 1 always). Returns the enemy.
func spawn(what, distance := -1.0, angle_degrees := 0.0, shielded := -1) -> Node3D:
	var scene: PackedScene = load(what) if what is String else what
	var enemy := scene.instantiate() as Node3D
	# Read when the enemy enters the tree, so it has to be set before it is added
	if "has_shield" in enemy:
		enemy.has_shield = spawn_shielded if shielded < 0 else shielded == 1
	enemies.add_child(enemy)
	var forward := -get_viewport().get_camera_3d().global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	forward = forward.rotated(Vector3.UP, -deg_to_rad(angle_degrees))
	var spot := player.global_position + forward * (spawn_distance if distance < 0.0 else distance)
	if distance < 0.0:
		spot = _free_spot(spot, forward.cross(Vector3.UP), enemy)
	enemy.global_position = spot
	var to_player := player.global_position - enemy.global_position
	to_player.y = 0.0
	if to_player.length() > 0.01:
		enemy.global_transform.basis = Basis.looking_at(to_player.normalized(), Vector3.UP).rotated(Vector3.UP, PI)
	if frozen:
		_freeze(enemy, true)
	return enemy


# Slides `spot` sideways (alternating right and left, further each time) until no other enemy is within
# SPAWN_SPACING of it, so repeated spawns line up beside each other instead of stacking.
func _free_spot(spot: Vector3, right: Vector3, ignore: Node3D) -> Vector3:
	for i in 40:
		var offset := ceili(i / 2.0) * (1 if i % 2 == 1 else -1)
		var candidate := spot + right * offset * SPAWN_SPACING
		var clear := true
		for other in enemies.get_children():
			if other == ignore or not other is Node3D or other.is_queued_for_deletion():
				continue
			var d: Vector3 = other.global_position - candidate
			d.y = 0.0
			if d.length() < SPAWN_SPACING:
				clear = false
				break
		if clear:
			return candidate
	return spot


# A horde of melee dodgers: `count` of them split between two rows ahead of you. The back row fans a little narrower
# than the front, so its dodgers stand in the front row's gaps and every one is in sight. They follow the shield and
# freeze toggles like any spawn. Returns them.
func spawn_horde(count := HORDE_SIZE) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	var front := ceili(count / 2.0)
	var back := count - front
	for i in count:
		var row := 0 if i < front else 1
		var in_row := front if row == 0 else back
		var slot := i if row == 0 else i - front
		var spread := HORDE_SPREAD if row == 0 else HORDE_SPREAD * float(back - 1) / maxi(front, 1)
		var t := 0.5 if in_row == 1 else float(slot) / (in_row - 1)
		spawned.append(spawn(HORDE_SCENE, HORDE_DISTANCES[row], lerpf(-spread / 2.0, spread / 2.0, t)))
	return spawned


func set_spawn_shielded(value: bool) -> void:
	spawn_shielded = value
	_update_help()


# The corner note: how to open the menu, and which switches are on (they change how the room behaves)
func _update_help() -> void:
	var on: Array[String] = []
	if frozen:
		on.append("enemies frozen")
	if spawn_shielded:
		on.append("shielded spawns")
	help_label.text = "TEST ROOM  (god mode: you can't die%s)\n" % (", unlimited ammo" if unlimited_ammo else "") \
			+ "F1  test menu" + ("   |   " + ", ".join(on) if not on.is_empty() else "")


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
	_update_help()


# Frozen enemies stay in physics so they can still be shot, chained and shield-bashed, and still flash, crackle and
# die. (Disabling the whole node would also pull every hitbox out of physics and leave shots passing through.) What
# stops is the physics loop, which runs their AI and movement; their animation, held on the frame it was on; and,
# by marking them a dummy, any switch into chasing or attacking.
func _freeze(enemy: Node, value: bool) -> void:
	var base := enemy as EnemyBase
	if value:
		if not base.has_meta("frozen_was_dummy"):
			base.set_meta("frozen_was_dummy", base.dummy)
		base.dummy = true
		base.velocity = Vector3.ZERO
		base.set_physics_process(false)
		if base.anim:
			base.anim.pause()
	else:
		if base.has_meta("frozen_was_dummy"):
			base.dummy = base.get_meta("frozen_was_dummy")
			base.remove_meta("frozen_was_dummy")
		base.set_physics_process(true)
		if base.anim and not base.anim.is_playing():
			base.anim.play()
