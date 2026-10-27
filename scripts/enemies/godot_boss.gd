extends EnemyBase
class_name GodotBoss

# The Godot robot boss. It has only four animations (idle, run, attack, die), so every move is built from those
# plus whole-body effects: the attack clip is a two-handed slam that rears back until about 0.35 s and thrusts
# at about 0.5 s, and holding it at the rear-up pose makes a stance for charging a slam or firing orbs.
#
# The fight has three phases, changing at set fractions of its health:
#   1 Brawler    melee, charge (crashing into a wall stuns it), shockwave slam
#   2 Summoner   gets a shield and fires slow orbs that can be parried back, which pops the shield and staggers it
#   3 Berserk    faster, glowing, shorter gaps between attacks
# On each change it rears up, roars and throws everyone back, and cannot be hurt for a moment.

const BLOOD_PARTICLES = preload("res://scripts/weapons/blood_particles.gd")
const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")
const ENERGY_BALL: PackedScene = preload("res://scenes/enemies/energy_ball.tscn")
const SpawnEffect = preload("res://scripts/levels/spawn_effect.gd")
# What the boss calls in, weighted by how often each is picked
const ADD_SCENES := [
	{"scene": preload("res://scenes/enemies/enemy_horde.tscn"), "weight": 3},
	{"scene": preload("res://scenes/enemies/enemy_dodger.tscn"), "weight": 2},
	{"scene": preload("res://scenes/enemies/enemy_flyer.tscn"), "weight": 2},
]

const PHASES := [
	{"name": "Brawler", "speed": 1.0, "gap": 1.6, "attacks": ["slam", "charge"]},
	{"name": "Summoner", "speed": 1.1, "gap": 1.3, "attacks": ["slam", "charge", "orbs", "summon"]},
	{"name": "Berserk", "speed": 1.3, "gap": 0.8, "attacks": ["slam", "charge", "orbs", "summon"]},
]

const ATTACK_ANIMATION_LENGTH := 1.33
const REAR_UP_POSE := 0.3          # seconds into the attack clip: arms back, head up
const THRUST_TIME := 0.55          # seconds into the attack clip when the hands are slammed forward

@export_category("Basic Attributes")
@export var health_bar: Control
@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.2
@export var vulnerable_multiplier := 1.5    # damage multiplier while it is stunned or open after an attack

@export_category("Hitbox")
@export var damage_window_start: float = 0.45
@export var damage_window_end: float = 0.85

@export_category("Charge Attack Attributes")
@export var charge_speed: float = 10.0
@export var charge_damage: float = 100.0
@export var charge_duration: float = 0.8
@export var charge_cooldown: float = 6.0
@export var charge_windup_time: float = 1.3
@export var charge_recovery_time: float = 2.1
@export var charge_steering := 1.2           # how sharply the charge turns towards the player (radians per second)
@export var crash_stun_time := 3.0           # stunned for this long after charging into a wall
@export var charge_material: StandardMaterial3D = preload("res://shaders/boss_charge_shader.tres")

@export_category("Shockwave Slam")
# Distances are in "boss lengths" (the boss's scale), so the attack keeps its proportions on any size of boss
@export var slam_radius := 5.5               # how far the wave travels
@export var slam_speed := 3.6                # how fast it travels
@export var slam_damage := 40.0
@export var slam_windup := 1.1
@export var slam_cooldown := 8.0
@export var slam_trigger_distance := 6.0     # it only slams when the player is this close

@export_category("Orb Volley")
@export var orb_count := 3
@export var orb_damage := 35.0
@export var orb_speed := 8.0
@export var orb_max_scale := 3.5
@export var orb_windup := 1.3
@export var orb_cooldown := 9.0
@export var orb_reflect_fraction := 0.08     # share of its full health a parried orb takes off
@export var orb_stun_time := 2.5

@export_category("Adds")
@export var summon_count := 3                # per summon in phase 2 (phase 3 calls in one more)
@export var intro_add_count := 4             # called in with the roar when phase 2 starts
@export var max_adds := 8                    # it will not summon while this many are alive
@export var summon_windup := 1.2
@export var summon_cooldown := 15.0
@export var add_spawn_distance := Vector2(6.0, 14.0)   # how far from the player (meters) adds appear

@export_category("Floor Hazard")
# Phase 3: tiles of the floor around the player light up, flash and burn, over and over
@export var hazard_enabled := true
@export var hazard_interval := 4.5           # seconds between patterns
@export var hazard_cells := 6                # tiles per pattern
@export var hazard_cell_size := 4.0          # meters
@export var hazard_damage := 20.0            # per tick, while standing in a burning tile
@export var hazard_warn_time := 1.4
@export var hazard_burn_time := 1.3
@export var hazard_spread := 2               # how many tiles from the player a pattern can reach

@export_category("Phases")
@export var phase_two_at := 0.66
@export var phase_three_at := 0.33
@export var phase_shield_hp := 800.0
@export var transition_time := 2.4

# --- Fight state ---
var phase := 1
var max_health := 0.0
var base_speed := 0.0
var invulnerable := false
var vulnerability := 1.0                     # set by the states that leave the boss open
var enraged := false
var hit_done := false
var cooldown_until := {}                     # attack name -> time (msec) it can be used again
var next_attack_msec := 0                    # no special attack before this
var next_think_msec := 0
var melee_ready_msec := 0
var pending_stun_time := 0.0
var original_material: Material
var attack_hitbox: Area3D
var shake_amount := 0.0
var next_hazard_msec := 0

@onready var footsteps: AudioStreamPlayer3D = $Footsteps
@onready var debug_label: Label3D = $DebugLabel


func _find_model_root() -> Node3D:
	return $godotman


func _find_anim() -> AnimationPlayer:
	return $"godotman/AnimationPlayer"


func _find_model() -> MeshInstance3D:
	return $godotman/godot_rig/Skeleton3D/godot_mesh


# The boss moves its own body, so the shared avoidance settings are not wanted
func _setup_navigation() -> void:
	nav.avoidance_enabled = false


func get_state_definitions() -> Dictionary:
	return {
		"Idle": IdleState.new(self),
		"Chase": ChaseState.new(self),
		"Melee": MeleeState.new(self),
		"Charge": ChargeState.new(self),
		"Slam": SlamState.new(self),
		"Orbs": OrbState.new(self),
		"Summon": SummonState.new(self),
		"Recovery": RecoveryState.new(self),
		"Stunned": StunnedState.new(self),
		"Transition": TransitionState.new(self),
		"Dead": DeadState.new(self),
	}


func _ready() -> void:
	super()
	max_health = health
	base_speed = movement_speed
	blood_scale = maxf(blood_scale, 0.75 * unit())   # a big enemy: fat streaks and big splats
	original_material = original_materials[0] if original_materials.size() > 0 else null

	attack_hitbox = get_node_or_null("godotman/godot_rig/Skeleton3D/RightHandAttach/RightAttackHitbox")
	if attack_hitbox != null:
		attack_hitbox.monitoring = false
		attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

	if health_bar:
		health_bar.set_max_health(health)
		health_bar.set_health(health)
	if debug_label:
		debug_label.visible = debug


func _physics_process(delta: float) -> void:
	super(delta)
	_update_hazard()
	if shake_amount > 0.0:
		model_root.position = model_rest.origin + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * shake_amount
	if debug and debug_label and get_viewport().get_camera_3d():
		debug_label.look_at(get_viewport().get_camera_3d().global_position, Vector3.UP)


# ---------------------------
# Helpers
# ---------------------------
# The boss's scale: distances in the fight are given in boss lengths
func unit() -> float:
	return global_basis.get_scale().x


func forward() -> Vector3:
	return global_basis.z.normalized()


func face_point(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.05:
		look_at(flat, Vector3.UP, true)


# The point on the floor under/over `point`, so warnings and waves sit on the real floor (the boss's own origin
# floats a little above it)
func floor_point(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 8.0)
	query.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return point
	return Vector3(point.x, hit["position"].y, point.z)


func flat_distance_to_target() -> float:
	if not is_instance_valid(target):
		return INF
	return Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()


# Holds the attack clip at the rear-up pose, and lets go of it again at a chosen speed
func hold_rear_up_pose() -> void:
	anim.play("attack")
	anim.seek(REAR_UP_POSE, true)
	anim.speed_scale = 0.0


func release_pose(speed := 2.2) -> void:
	anim.speed_scale = speed


func set_shake(amount: float) -> void:
	shake_amount = amount
	if amount <= 0.0 and model_root != null:
		model_root.position = model_rest.origin


func play_sfx(paths: String) -> void:
	Audio.play(paths)


func shake_player_camera(pitch: float, yaw: float) -> void:
	if is_instance_valid(target) and target.has_method("apply_camera_kick"):
		target.apply_camera_kick(pitch, randf_range(-yaw, yaw))


func _update_footsteps() -> void:
	# Horizontal movement speed (ignore vertical)
	var horizontal_speed := Vector3(velocity.x, 0, velocity.z).length()
	var should_play := is_on_floor() and horizontal_speed > 0.1
	if should_play:
		if not footsteps.playing:
			footsteps.play()
	elif footsteps.playing:
		footsteps.stop()


# ---------------------------
# Visuals: charge material, glow, shield
# ---------------------------
func make_mesh_materials_unique(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh.duplicate()
	for i in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(i)
		if mat:
			mesh.surface_set_material(i, mat.duplicate())
	mesh_instance.mesh = mesh


func apply_charge_material() -> void:
	if model:
		model.set_surface_override_material(0, charge_material)


func remove_charge_material() -> void:
	if model:
		model.set_surface_override_material(0, shield_material if shield != null and is_instance_valid(shield) else original_material)


# Fades the body's emission to a colour (or off). The base material only: the glass shield has no emission.
func set_glow(active: bool, color := Color(1.0, 0.4, 0.1), energy := 3.0, seconds := 0.6) -> void:
	var mat := model.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	if active:
		mat.emission_enabled = true
		mat.emission = color
		create_tween().tween_property(mat, "emission_energy_multiplier", energy, seconds)
	else:
		var tween := create_tween()
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, seconds)
		tween.tween_callback(_emission_off.bind(mat))


func _emission_off(mat: StandardMaterial3D) -> void:
	if mat.emission_energy_multiplier <= 0.1:
		mat.emission_enabled = false


# The glow it keeps between attacks once enraged
func settle_glow() -> void:
	if enraged:
		set_glow(true, Color(1.0, 0.15, 0.1), 1.4, 0.4)
	else:
		set_glow(false)


func _add_phase_shield() -> void:
	if shield != null and is_instance_valid(shield):
		return
	var new_shield = SHIELD_SCENE.instantiate()
	new_shield.name = "Shield"
	new_shield.max_hp = phase_shield_hp
	new_shield.hp = phase_shield_hp
	add_child(new_shield)
	shield = new_shield
	shield.connect("shield_destroyed", Callable(self, "_on_shield_destroyed"))
	shield_material = shield_material.duplicate()
	apply_shield_material()


# ---------------------------
# Vision
# ---------------------------
func _on_vision_area_body_entered(body: Node3D) -> void:
	if body == target and state != states["Dead"] and state == states["Idle"]:
		if health_bar:
			health_bar.show_bar()
		next_attack_msec = Time.get_ticks_msec() + 1500
		change_state("Chase")


func _on_body_entered(body: Node3D) -> void:
	_on_vision_area_body_entered(body)


func _on_vision_area_body_exited(_body: Node3D) -> void:
	pass


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	# only damage the target and only once per attack
	if body == target and not hit_done:
		if body.has_method("damage"):
			body.damage(damage_to_player)
		hit_done = true


# ---------------------------
# Choosing attacks
# ---------------------------
func melee_range() -> float:
	return 0.9 * unit()


# Called by the chase state: starts a special attack when one is ready and fits the distance
func choose_special(distance: float) -> bool:
	var now := Time.get_ticks_msec()
	if now < next_think_msec or now < next_attack_msec:
		return false
	next_think_msec = now + 250
	var options: Array[String] = []
	var length := unit()
	for attack in PHASES[phase - 1]["attacks"]:
		if now < int(cooldown_until.get(attack, 0)):
			continue
		match attack:
			"slam":
				if distance <= slam_trigger_distance * length:
					options.append(attack)
			"charge":
				if distance >= 1.5 * length and _lane_is_clear():
					options.append(attack)
			"orbs":
				if distance >= 1.8 * length:
					options.append(attack)
			"summon":
				if alive_adds() <= max_adds - summon_count:
					options.append(attack)
	if options.is_empty():
		return false
	var pick: String = options.pick_random()
	var cooldown := {"slam": slam_cooldown, "charge": charge_cooldown, "orbs": orb_cooldown, "summon": summon_cooldown}[pick] as float
	cooldown_until[pick] = now + int(cooldown * randf_range(0.85, 1.15) * 1000.0)
	change_state({"slam": "Slam", "charge": "Charge", "orbs": "Orbs", "summon": "Summon"}[pick])
	return true


# Nothing solid between the boss and the player, so a charge has a lane to run along
func _lane_is_clear() -> bool:
	var from := global_position + Vector3.UP * unit() * 0.6
	var to := target.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = 2
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func start_attack_gap() -> void:
	next_attack_msec = Time.get_ticks_msec() + int(float(PHASES[phase - 1]["gap"]) * 1000.0)


# ---------------------------
# Damage and phases
# ---------------------------
func damage(amount: float, multiplier: float = 1.0) -> void:
	if destroyed or invulnerable:
		return
	var dealt := amount * multiplier
	if shield != null and is_instance_valid(shield):
		dealt = shield.absorb_damage(amount)
	dealt *= vulnerability
	_lose_health(dealt)


func _lose_health(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	if health_bar:
		health_bar.set_health(health)
	if health <= 0.0:
		_die()
		return
	_check_phase()


func _check_phase() -> void:
	if destroyed or state == states["Transition"]:
		return
	var ratio := health / max_health
	var next := phase
	if phase == 1 and ratio <= phase_two_at:
		next = 2
	elif phase == 2 and ratio <= phase_three_at:
		next = 3
	if next != phase:
		phase = next
		change_state("Transition")


# ---------------------------
# Adds
# ---------------------------
func alive_adds() -> int:
	var count := 0
	for add in get_tree().get_nodes_in_group("BossAdd"):
		if is_instance_valid(add) and not add.get("destroyed"):
			count += 1
	return count


# Calls in a few enemies around the player, each with the spawn flash. Returns how many appeared.
func summon_adds(count: int) -> int:
	count = mini(count, max_adds - alive_adds())
	var spawned := 0
	for i in count:
		var point = _find_add_point()
		if point == null:
			continue
		var scene: PackedScene = _pick_add_scene()
		var add = scene.instantiate()
		add.target = target
		add.add_to_group("BossAdd")
		get_parent().add_child(add)
		add.global_position = point + Vector3.UP * 0.2
		SpawnEffect.play(get_tree(), point)
		spawned += 1
	return spawned


func _pick_add_scene() -> PackedScene:
	var total := 0
	for entry in ADD_SCENES:
		total += int(entry["weight"])
	var roll := randi() % total
	for entry in ADD_SCENES:
		roll -= int(entry["weight"])
		if roll < 0:
			return entry["scene"]
	return ADD_SCENES[0]["scene"]


# A spot on the navigation mesh around the player, not too close and not in a wall
func _find_add_point():
	var map := nav.get_navigation_map()
	var centre: Vector3 = target.global_position if is_instance_valid(target) else global_position
	for attempt in 14:
		var angle := randf() * TAU
		var distance := randf_range(add_spawn_distance.x, add_spawn_distance.y)
		var candidate := centre + Vector3(sin(angle), 0.0, cos(angle)) * distance
		var snapped_point := NavigationServer3D.map_get_closest_point(map, candidate)
		if Vector2(snapped_point.x - candidate.x, snapped_point.z - candidate.z).length() > 1.5:
			continue
		if absf(snapped_point.y - centre.y) > 3.0:
			continue
		return snapped_point
	return null


func kill_adds() -> void:
	for add in get_tree().get_nodes_in_group("BossAdd"):
		if is_instance_valid(add) and add.has_method("damage") and not add.get("destroyed"):
			add.damage(1.0e9)


# ---------------------------
# Floor hazard
# ---------------------------
func _update_hazard() -> void:
	if not hazard_enabled or phase < 3 or destroyed or invulnerable or not is_instance_valid(target):
		return
	if state == states["Transition"] or state == states["Idle"]:
		return
	var now := Time.get_ticks_msec()
	if now < next_hazard_msec:
		return
	next_hazard_msec = now + int(hazard_interval * 1000.0 * randf_range(0.85, 1.15))
	spawn_hazard_pattern()


# Tiles on a grid fixed to the world: always one under the player, the rest scattered close around them
func spawn_hazard_pattern() -> void:
	var size := hazard_cell_size
	var player_floor := floor_point(target.global_position)
	var reference_y := floor_point(global_position).y
	var chosen := {}
	var origin := Vector2i(roundi(player_floor.x / size), roundi(player_floor.z / size))
	chosen[origin] = true
	var attempts := 0
	while chosen.size() < hazard_cells and attempts < 40:
		attempts += 1
		var offset := Vector2i(randi_range(-hazard_spread, hazard_spread), randi_range(-hazard_spread, hazard_spread))
		chosen[origin + offset] = true
	var floor_cells: Array = []
	for key in chosen:
		var centre := floor_point(Vector3(float(key.x) * size, player_floor.y + 1.0, float(key.y) * size))
		if absf(centre.y - reference_y) > 1.5 or centre.y < player_floor.y - 1.5:
			continue  # not part of the arena floor (a wall, a ledge or a drop)
		floor_cells.append(centre)
	if floor_cells.is_empty():
		return
	BossFloorHazard.spawn(get_tree(), floor_cells, size, hazard_damage, hazard_warn_time, hazard_burn_time)


# Set up the phase's numbers: speed, attack gaps, shield and glow. Done at the moment of the roar.
func apply_phase() -> void:
	var data: Dictionary = PHASES[phase - 1]
	movement_speed = base_speed * float(data["speed"])
	enraged = phase >= 3
	if phase == 2:
		_add_phase_shield()
		summon_adds(intro_add_count)
	if phase >= 3:
		next_hazard_msec = Time.get_ticks_msec() + 1500
	settle_glow()


# A parried orb came back: it pops the shield, takes a big bite out of its health and staggers it
func on_reflected_orb_hit(_orb_damage: float) -> void:
	if destroyed or invulnerable:
		return
	if shield != null and is_instance_valid(shield):
		shield.absorb_damage(1.0e9)
	flinch(global_position + Vector3.UP * unit() * 1.2, 3.0)
	shake_player_camera(0.05, 0.02)
	play_sfx("assets/audio/sfx/boss/Boss_Hit1.wav, assets/audio/sfx/boss/Boss_Hit2.wav")
	_lose_health(max_health * orb_reflect_fraction)
	if not destroyed and state != states["Transition"]:
		pending_stun_time = orb_stun_time
		change_state("Stunned")


# The boss is big, so it only flinches a little
func flinch(world_point: Vector3, strength := 1.0) -> void:
	super(world_point, strength * 0.4)


func _die() -> void:
	if destroyed:
		return
	kill_adds()
	change_state("Dead")


# ---------------------------
# States
# ---------------------------
class BossState:
	var enemy: GodotBoss

	func _init(e: GodotBoss) -> void:
		enemy = e


class IdleState extends BossState:
	func enter() -> void:
		enemy.anim.speed_scale = 1.0
		enemy.anim.play("idle")
		enemy.velocity = Vector3.ZERO


class ChaseState extends BossState:
	func enter() -> void:
		enemy.anim.speed_scale = 1.0
		enemy.anim.play("run")

	func update(_delta: float) -> void:
		if not is_instance_valid(enemy.target):
			return
		var distance := enemy.flat_distance_to_target()
		# A special attack that is ready comes before a swing, so staying in its face doesn't avoid the slam
		if enemy.choose_special(distance):
			return
		if distance <= enemy.melee_range() and Time.get_ticks_msec() >= enemy.melee_ready_msec:
			enemy.change_state("Melee")
			return

		enemy.nav.set_target_position(enemy.target.global_position)
		var next_position := enemy.nav.get_next_path_position()
		var direction := (next_position - enemy.global_position).normalized()
		enemy.velocity = direction * enemy.movement_speed
		enemy.face_point(enemy.target.global_position)
		enemy.move_and_slide()
		enemy._update_footsteps()


# A swing: the clip's own rear-up is the warning, shown on the floor where the hands will land
class MeleeState extends BossState:
	var elapsed := 0.0
	var warning: BossTelegraph
	var hitbox_on := false

	func enter() -> void:
		elapsed = 0.0
		hitbox_on = false
		enemy.hit_done = false
		enemy.is_attacking = true
		enemy.velocity = Vector3.ZERO
		enemy.melee_ready_msec = Time.get_ticks_msec() + int(enemy.attack_cooldown * 1000.0)
		enemy.anim.speed_scale = 1.0
		enemy.anim.play("attack")
		var length := enemy.unit()
		warning = BossTelegraph.circle(enemy.get_tree(), enemy.floor_point(enemy.global_position + enemy.forward() * 0.55 * length), 0.75 * length)
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Hit1.wav, assets/audio/sfx/boss/Boss_Hit2.wav, assets/audio/sfx/boss/Boss_Hit3.wav")

	func update(delta: float) -> void:
		elapsed += delta
		if elapsed < enemy.damage_window_start and is_instance_valid(enemy.target):
			enemy.face_point(enemy.target.global_position)
			warning.global_position = enemy.floor_point(enemy.global_position + enemy.forward() * 0.55 * enemy.unit()) + Vector3.UP * BossTelegraph.FLOOR_LIFT
			warning.set_progress(elapsed / enemy.damage_window_start)
		if not hitbox_on and elapsed >= enemy.damage_window_start and elapsed < enemy.damage_window_end:
			hitbox_on = true
			enemy.hit_done = false
			if enemy.attack_hitbox:
				enemy.attack_hitbox.monitoring = true
			warning.finish(0.1)
		if hitbox_on and elapsed >= enemy.damage_window_end:
			hitbox_on = false
			if enemy.attack_hitbox:
				enemy.attack_hitbox.monitoring = false
		if elapsed >= ATTACK_ANIMATION_LENGTH:
			enemy.change_state("Chase")

	func exit() -> void:
		enemy.is_attacking = false
		if enemy.attack_hitbox:
			enemy.attack_hitbox.monitoring = false
		if is_instance_valid(warning):
			warning.finish(0.1)


# Winds up with a lane on the floor showing where it will run, then rushes. It keeps turning a little while
# running, but hitting a wall stuns it, so the way to beat it is to sidestep into one.
class ChargeState extends BossState:
	enum Phase { WINDUP, CHARGING }

	var phase := Phase.WINDUP
	var elapsed := 0.0
	var direction := Vector3.ZERO
	var lane: BossTelegraph
	var lane_length := 20.0
	var hit_player := false

	func enter() -> void:
		phase = Phase.WINDUP
		elapsed = 0.0
		hit_player = false
		enemy.is_attacking = true
		enemy.velocity = Vector3.ZERO
		direction = _aim()
		enemy.apply_charge_material()
		enemy.set_glow(true)
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar1.wav, assets/audio/sfx/boss/Boss_Roar2.wav")
		enemy.anim.speed_scale = 0.7
		enemy.anim.play("idle")
		lane_length = enemy.charge_speed * enemy.charge_duration
		var start := enemy.floor_point(enemy.global_position)
		lane = BossTelegraph.lane(enemy.get_tree(), start, start + direction * lane_length, 1.7 * enemy.unit())

	func _aim() -> Vector3:
		var to_target := enemy.target.global_position - enemy.global_position
		to_target.y = 0.0
		return to_target.normalized() if to_target.length() > 0.01 else enemy.forward()

	func update(delta: float) -> void:
		elapsed += delta
		match phase:
			Phase.WINDUP:
				# It keeps aiming for most of the wind-up and then commits, so the player can sidestep
				if elapsed < enemy.charge_windup_time * 0.7 and is_instance_valid(enemy.target):
					direction = direction.slerp(_aim(), clampf(6.0 * delta, 0.0, 1.0)).normalized()
				enemy.face_point(enemy.global_position + direction)
				enemy.set_shake(0.02 * (elapsed / enemy.charge_windup_time))
				var start := enemy.floor_point(enemy.global_position)
				lane.set_lane(start, start + direction * lane_length, 1.7 * enemy.unit())
				lane.set_progress(elapsed / enemy.charge_windup_time)
				if elapsed >= enemy.charge_windup_time:
					phase = Phase.CHARGING
					elapsed = 0.0
					enemy.set_shake(0.0)
					enemy.anim.speed_scale = 1.0
					enemy.anim.play("run")
					lane.finish(0.15)
			Phase.CHARGING:
				if is_instance_valid(enemy.target):
					direction = direction.slerp(_aim(), clampf(enemy.charge_steering * delta, 0.0, 1.0)).normalized()
				enemy.velocity = direction * enemy.charge_speed
				enemy.face_point(enemy.global_position + direction)
				enemy.move_and_slide()
				enemy._update_footsteps()

				if not hit_player and is_instance_valid(enemy.target) and enemy.flat_distance_to_target() <= 0.6 * enemy.unit():
					hit_player = true
					if enemy.target.has_method("damage"):
						enemy.target.damage(enemy.charge_damage)
					if enemy.target.has_method("apply_push"):
						enemy.target.apply_push(direction * 25.0)
					enemy.shake_player_camera(0.08, 0.03)
					enemy.change_state("Recovery")
					return
				if _hit_a_wall():
					enemy.pending_stun_time = enemy.crash_stun_time
					enemy.change_state("Stunned")
					return
				if elapsed >= enemy.charge_duration:
					enemy.change_state("Recovery")

	func _hit_a_wall() -> bool:
		for i in enemy.get_slide_collision_count():
			var collision := enemy.get_slide_collision(i)
			if absf(collision.get_normal().y) < 0.4 and collision.get_collider() != enemy.target:
				return true
		return false

	func exit() -> void:
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.remove_charge_material()
		enemy.settle_glow()
		if is_instance_valid(lane):
			lane.finish(0.1)


# Rears up, then brings both hands down: a shockwave runs out along the floor and hurts anyone on the ground
class SlamState extends BossState:
	enum Phase { WINDUP, STRIKE, HOLD }

	var phase := Phase.WINDUP
	var elapsed := 0.0
	var warning: BossTelegraph
	var reach := 20.0

	func enter() -> void:
		phase = Phase.WINDUP
		elapsed = 0.0
		enemy.is_attacking = true
		enemy.velocity = Vector3.ZERO
		reach = enemy.slam_radius * enemy.unit()
		enemy.hold_rear_up_pose()
		enemy.set_glow(true)
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar1.wav, assets/audio/sfx/boss/Boss_Roar2.wav")
		warning = BossTelegraph.circle(enemy.get_tree(), enemy.floor_point(enemy.global_position), reach)

	func update(delta: float) -> void:
		elapsed += delta
		match phase:
			Phase.WINDUP:
				if is_instance_valid(enemy.target):
					enemy.face_point(enemy.target.global_position)
				enemy.set_shake(0.025 * (elapsed / enemy.slam_windup))
				warning.global_position = enemy.floor_point(enemy.global_position) + Vector3.UP * BossTelegraph.FLOOR_LIFT
				warning.set_progress(elapsed / enemy.slam_windup)
				if elapsed >= enemy.slam_windup:
					phase = Phase.STRIKE
					elapsed = 0.0
					enemy.set_shake(0.0)
					enemy.release_pose(2.4)
			Phase.STRIKE:
				if enemy.anim.current_animation_position >= THRUST_TIME or elapsed > 0.6:
					phase = Phase.HOLD
					elapsed = 0.0
					_impact()
			Phase.HOLD:
				if elapsed >= 0.7:
					enemy.change_state("Recovery")

	func _impact() -> void:
		var length := enemy.unit()
		var centre := enemy.floor_point(enemy.global_position + enemy.forward() * 0.6 * length)
		BossShockwave.spawn(enemy.get_tree(), centre, reach, enemy.slam_speed * length, enemy.slam_damage)
		ImpactParticles.spawn(enemy.get_tree(), centre + Vector3.UP * 0.3, Vector3.UP, 2.5)
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Hit1.wav, assets/audio/sfx/boss/Boss_Hit2.wav, assets/audio/sfx/boss/Boss_Hit3.wav")
		enemy.shake_player_camera(0.1, 0.03)
		warning.finish(0.1)
		enemy.settle_glow()

	func exit() -> void:
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.anim.speed_scale = 1.0
		enemy.settle_glow()
		if is_instance_valid(warning):
			warning.finish(0.1)


# Rears up and fires slow orbs at the player. A parried orb flies back, pops the shield and staggers the boss.
class OrbState extends BossState:
	enum Phase { WINDUP, FIRING, HOLD }

	var phase := Phase.WINDUP
	var elapsed := 0.0
	var fired := 0
	var total := 3

	func enter() -> void:
		phase = Phase.WINDUP
		elapsed = 0.0
		fired = 0
		total = enemy.orb_count + (2 if enemy.phase >= 3 else 0)
		enemy.is_attacking = true
		enemy.velocity = Vector3.ZERO
		enemy.hold_rear_up_pose()
		enemy.set_glow(true, Color(1.0, 0.2, 0.8))
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar1.wav, assets/audio/sfx/boss/Boss_Roar2.wav")

	func update(delta: float) -> void:
		elapsed += delta
		if is_instance_valid(enemy.target):
			enemy.face_point(enemy.target.global_position)
		match phase:
			Phase.WINDUP:
				enemy.set_shake(0.02 * (elapsed / enemy.orb_windup))
				if elapsed >= enemy.orb_windup:
					phase = Phase.FIRING
					elapsed = 0.0
					enemy.set_shake(0.0)
			Phase.FIRING:
				if fired < total and elapsed >= 0.3 * float(fired):
					_fire(fired)
					fired += 1
				elif fired >= total and elapsed >= 0.3 * float(total) + 0.4:
					phase = Phase.HOLD
					elapsed = 0.0
					enemy.release_pose(2.0)
			Phase.HOLD:
				if elapsed >= 0.6:
					enemy.change_state("Recovery")

	func _fire(index: int) -> void:
		if not is_instance_valid(enemy.target):
			return
		var length := enemy.unit()
		var origin := enemy.global_position + Vector3.UP * 1.0 * length + enemy.forward() * 0.9 * length
		var aim := (enemy.target.global_position + Vector3.UP - origin).normalized()
		aim = aim.rotated(Vector3.UP, (float(index) - float(total - 1) * 0.5) * deg_to_rad(16.0))
		var ball = ENERGY_BALL.instantiate()
		ball.damage = enemy.orb_damage
		ball.SPEED = enemy.orb_speed
		ball.max_scale = enemy.orb_max_scale
		ball.scale_speed = 2.0
		ball.turn_rate = 1.1
		ball.shooter = enemy
		ball.always_return_to_shooter = true
		ball.get_node("SelfQueueTimer").wait_time = 9.0
		enemy.get_tree().current_scene.add_child(ball)
		ball.global_position = origin
		ball.velocity = aim * ball.SPEED
		ball.set_target(enemy.target)
		Audio.play_at(origin, "assets/audio/sfx/enemies/Enemy_Shoot1_PitchedUp.wav, assets/audio/sfx/enemies/Enemy_Shoot2_PitchedUp.wav")
		enemy.shake_player_camera(0.02, 0.01)

	func exit() -> void:
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.anim.speed_scale = 1.0
		enemy.settle_glow()


# Rears up and calls in reinforcements around the player. Vulnerable while it does.
class SummonState extends BossState:
	enum Phase { WINDUP, CALL, HOLD }

	var phase := Phase.WINDUP
	var elapsed := 0.0

	func enter() -> void:
		phase = Phase.WINDUP
		elapsed = 0.0
		enemy.is_attacking = true
		enemy.velocity = Vector3.ZERO
		enemy.hold_rear_up_pose()
		enemy.set_glow(true, Color(0.5, 0.4, 1.0))
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar1.wav, assets/audio/sfx/boss/Boss_Roar2.wav")

	func update(delta: float) -> void:
		elapsed += delta
		if is_instance_valid(enemy.target):
			enemy.face_point(enemy.target.global_position)
		match phase:
			Phase.WINDUP:
				enemy.set_shake(0.025 * (elapsed / enemy.summon_windup))
				if elapsed >= enemy.summon_windup:
					phase = Phase.CALL
					elapsed = 0.0
					enemy.set_shake(0.0)
					enemy.release_pose(2.2)
					enemy.summon_adds(enemy.summon_count + (1 if enemy.phase >= 3 else 0))
					enemy.shake_player_camera(0.05, 0.02)
					enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar2.wav")
			Phase.CALL:
				if elapsed >= 0.5:
					phase = Phase.HOLD
					elapsed = 0.0
			Phase.HOLD:
				if elapsed >= 0.5:
					enemy.change_state("Recovery")

	func exit() -> void:
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.anim.speed_scale = 1.0
		enemy.settle_glow()


# Tired after an attack: slow, and takes extra damage
class RecoveryState extends BossState:
	var elapsed := 0.0
	var duration := 2.1

	func enter() -> void:
		elapsed = 0.0
		duration = enemy.charge_recovery_time
		enemy.velocity = Vector3.ZERO
		enemy.vulnerability = 1.0 + (enemy.vulnerable_multiplier - 1.0) * 0.5
		enemy.anim.speed_scale = 0.6
		enemy.anim.play("idle")

	func update(delta: float) -> void:
		elapsed += delta
		if elapsed >= duration:
			enemy.change_state("Chase")

	func exit() -> void:
		enemy.vulnerability = 1.0
		enemy.anim.speed_scale = 1.0
		enemy.start_attack_gap()


# Dazed (after hitting a wall or taking a parried orb): helpless and takes a lot more damage
class StunnedState extends BossState:
	var elapsed := 0.0
	var duration := 3.0

	func enter() -> void:
		elapsed = 0.0
		duration = enemy.pending_stun_time
		enemy.velocity = Vector3.ZERO
		enemy.vulnerability = enemy.vulnerable_multiplier
		enemy.anim.speed_scale = 0.35
		enemy.anim.play("idle")
		enemy.set_glow(true, Color(0.4, 0.75, 1.0), 2.0, 0.2)
		enemy.shake_player_camera(0.06, 0.02)

	func update(delta: float) -> void:
		elapsed += delta
		enemy.set_shake(0.012 + 0.01 * sin(elapsed * 30.0))
		if elapsed >= duration:
			enemy.change_state("Chase")

	func exit() -> void:
		enemy.vulnerability = 1.0
		enemy.anim.speed_scale = 1.0
		enemy.set_shake(0.0)
		enemy.settle_glow()
		enemy.start_attack_gap()


# Between phases: rears up, roars and throws the player back, and cannot be hurt. The new phase takes hold at
# the moment of the roar.
class TransitionState extends BossState:
	enum Phase { REAR, ROAR }

	var phase := Phase.REAR
	var elapsed := 0.0

	func enter() -> void:
		phase = Phase.REAR
		elapsed = 0.0
		_roared = false
		enemy.invulnerable = true
		enemy.is_attacking = true
		enemy.velocity = Vector3.ZERO
		enemy.vulnerability = 1.0
		enemy.remove_charge_material()
		enemy.hold_rear_up_pose()
		enemy.set_glow(true, Color(1.0, 0.9, 0.7), 3.0, 0.3)
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar1.wav, assets/audio/sfx/boss/Boss_Roar2.wav")

	func update(delta: float) -> void:
		elapsed += delta
		match phase:
			Phase.REAR:
				enemy.set_shake(0.03 * minf(elapsed / (enemy.transition_time * 0.45), 1.0))
				if elapsed >= enemy.transition_time * 0.45:
					phase = Phase.ROAR
					elapsed = 0.0
					enemy.set_shake(0.0)
					enemy.release_pose(2.2)
			Phase.ROAR:
				if not _roared and (enemy.anim.current_animation_position >= THRUST_TIME - 0.05 or elapsed >= 0.45):
					_roar()
				if elapsed >= enemy.transition_time * 0.55:
					enemy.change_state("Chase")

	var _roared := false

	func _roar() -> void:
		_roared = true
		var length := enemy.unit()
		BossShockwave.spawn(enemy.get_tree(), enemy.floor_point(enemy.global_position), 3.5 * length, 4.0 * length, 0.0, true)
		enemy.shake_player_camera(0.12, 0.04)
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Roar2.wav")
		enemy.apply_phase()

	func exit() -> void:
		_roared = false
		enemy.invulnerable = false
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.anim.speed_scale = 1.0
		enemy.settle_glow()
		enemy.start_attack_gap()


class DeadState extends BossState:
	func enter() -> void:
		enemy.destroyed = true
		enemy.invulnerable = true
		enemy.velocity = Vector3.ZERO
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.remove_charge_material()
		for area in enemy.find_children("*", "Area3D", true, false):
			area.set_deferred("collision_layer", 0)
			area.set_deferred("monitorable", false)
			area.set_deferred("monitoring", false)
		enemy.collision_layer = 0
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Death1.wav")
		enemy.anim.speed_scale = 1.0
		enemy.anim.play("die")
		if enemy.health_bar:
			enemy.health_bar.hide_bar()
		_finish()

	func _finish() -> void:
		await enemy.anim.animation_finished
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			return
		# It hits the floor and bursts, like the smaller enemies
		var length := enemy.unit()
		for offset in [Vector3.ZERO, Vector3(1, 0, 0.6), Vector3(-1, 0, -0.6)]:
			BLOOD_PARTICLES.spawn_burst(enemy.get_tree(), enemy.global_position + offset * length * 0.5 + Vector3.UP * 0.4 * length, 1.4, enemy.blood_scale)
		await enemy.get_tree().create_timer(1.2).timeout
		GameManager.win()
