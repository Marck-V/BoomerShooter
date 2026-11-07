extends EnemyBase
class_name EnemyHorde

const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.533
@export var melee_range: float = 1.0
# Delay damaging player till animation is at the right part
@export var damage_window_start: float = 0.2
@export var damage_window_end: float = 1.1
@export var vision_range: float = 10.0
# Once chasing it only gives up beyond this distance, so a route that detours out of its vision area (a ramp out of a
# pit) doesn't leave it standing idle halfway
@export var chase_leash: float = 40.0

@export_group("Lunge")
# While closing in from range the enemy sometimes crouches, dashes and punches. The fist glows yellow for
# the whole lunge, and a parry timed on that punch stuns the enemy. Close up it just uses the normal punch.
@export var lunge_enabled := true
@export var lunge_min_range := 4.0          # closer than this it uses the normal attack
@export var lunge_max_range := 9.0
@export var lunge_windup := 0.55            # crouch while the fist charges up
@export var lunge_dash_time := 0.45         # longest the dash can last
@export var lunge_speed := 15.0
@export var lunge_strike_range := 1.7       # the dash ends and the punch starts at this distance
@export var lunge_follow_through := 0.3     # seconds the punch keeps moving the enemy forward
@export var lunge_reach := 0.9              # ...until it is this close
@export var lunge_shove_speed := 22.0       # how hard a lunge shoves a blocking player aside
@export var lunge_shove_clearance := 2.5    # free space needed on the side the player is shoved towards
@export var lunge_cooldown_min := 3.0
@export var lunge_cooldown_max := 6.0
@export var lunge_windup_animation := "Crouch_Idle"
@export var parry_lead := 0.1               # real seconds before a yellow blow connects that it can be parried
@export var parry_late := 0.08              # ...and how long after it would have connected (if it missed)
@export var parry_stun_time := 1.6
@export var parry_stun_damage_multiplier := 1.5

@export_group("Crowd")
# Melee enemies take turns, but only when there is a crowd: a few hold an attack slot and go for the player, while
# the rest wait on their own spot of a ring around them, standing on guard and shuffling a few steps now and then.
# After an attack an enemy keeps its turn (and presses in, just out of reach, until it can strike again) unless
# others are waiting for one; then it falls back to the ring and lets them in.
@export var ring_radius_min := 4.5
@export var ring_radius_max := 8.0
@export var engage_distance := 9.0          # a free slot is only claimed this close
@export var waiting_walk_speed := 1.7       # m/s while shuffling round the ring or pressing in
@export var reposition_speed := 3.5         # m/s (a jog) when its waiting spot is further than REPOSITION_GAP
@export var shuffle_interval := Vector2(1.2, 3.0)   # seconds standing between shuffles
@export var shuffle_angle := Vector2(0.2, 0.45)    # radians round the ring one shuffle covers
@export var press_gap := 1.2                # how far outside its reach it waits while its attack cools down
@export var crowd_rest := Vector2(1.0, 2.5) # in a crowd, seconds after its cooldown before it may take another turn

@export_group("Gap jump")
# Where the level has a NavigationLink3D across a small gap, the enemy jumps it: Jump_Start sped up across the
# flight, an arc over the gap, then Jump_Land. Only used while chasing.
@export var jump_enabled := true
@export var jump_speed := 6.0               # horizontal speed of the jump, in units per second
@export var jump_min_time := 0.45
@export var jump_max_time := 0.9
@export var jump_height := 0.9              # how far above the straight line the arc peaks (at least dy + 0.6 when jumping up)
@export var jump_land_time := 0.3           # recovery crouch before it carries on

@export_group("Punch combo")
# Up close the enemy throws a 1-2 instead of a single swing: a left jab (Punch_Jab) and then, if the player
# is still in reach, a heavier right cross (Punch_Cross). The lunge keeps its single glowing swing.
@export var combo_chain_range := 1.9        # the cross only follows if the player is within this distance
@export var combo_step_distance := 0.8      # it steps in during the combo until it is this close, so every punch reaches
@export var combo_step_speed := 3.0

# Each hit: which hand, when its hitbox is live (seconds into the clip, read from the fists' positions while
# the animation plays) and how much of damage_to_player it deals.
const COMBO := [
	{"animation": "Punch_Jab", "length": 0.87, "hits": [
		{"hand": "L", "start": 0.15, "end": 0.42, "damage": 0.3},
	]},
	{"animation": "Punch_Cross", "length": 1.0, "hits": [
		{"hand": "R", "start": 0.2, "end": 0.62, "damage": 0.8},
	]},
]

const MAX_SIMULTANEOUS_LUNGES := 2
const MAX_ATTACKERS := 3
const FLANK_SPREAD := deg_to_rad(110.0)     # furthest off the direct line it fans out
const FLANK_MAX_HEIGHT_GAP := 1.5           # above this the player is on another level: take the direct route
const FLANK_WALL_MARGIN := 1.0
const SLOT_HOLD_TIME := 4.0                 # gives up a slot it has not used in this long
const RUN_ANIMATION := "Sprint"
# Moving while it waits is a walk for the short shuffles and a jog to get to a spot further off, each sped up or
# slowed to the actual speed so the feet keep up with the ground (the walk's feet cover about 1 m/s, the jog's
# about 2.5). StrafeTwist turns the legs the way it goes.
const CIRCLE_ANIMATION := "Walk"
const REPOSITION_ANIMATION := "Jog_Fwd"
const WAITING_CLIP_SPEEDS := {"Walk": 1.0, "Jog_Fwd": 2.5}
const CIRCLE_PLAYBACK_RANGE := Vector2(0.8, 1.9)
const REPOSITION_GAP := 1.2                 # further than this from its spot, it jogs there
const ARRIVED := 0.5                        # this close to its spot it stands still
const STAND_SPEED := 0.35                   # moving slower than this, it stands on guard instead of walking

static var attack_slot_holders: Array = []
const ParryFx = preload("res://scripts/enemies/parry_fx.gd")
const GlowTrail = preload("res://scripts/enemies/glow_trail.gd")
const ARM_HEAT_SHADER: Shader = preload("res://shaders/enemies/arm_heat.gdshader")
const AURA_COLOR := Color(1.0, 0.75, 0.15)
const GLOW_LIGHT_COLOR := Color(1.0, 0.8, 0.2)
const FIST_OFFSET := Vector3(0.0, 0.1, 0.0)  # from the hand bone (at the wrist) to the middle of the fist
const WISP_RADIUS := 0.09
const RING_START_SCALE := 2.4              # the ring closes in from here and lands on the fist as the parry window opens
const RING_END_SCALE := 0.5
const FIST_GLINT_SIZE := 1.3

var hit_done := false
var holds_attack_slot := false
var slot_held_time := 0.0
var flank_assigned := false
var flank_angle := 0.0
var flank_radius := 0.0
var circle_direction := 1.0
var shuffle_timer := 0.0
var rejoin_ring := false                    # it just gave up its turn: pick a waiting spot on its own side
var next_turn_msec := 0                     # in a crowd, no new turn before this, so the others get theirs
var hit_damage_scale := 1.0                 # share of damage_to_player the current hit deals
var left_hitbox: Area3D
var attack_token := 0                       # bumped when an attack is cancelled, so a running attack stops
var parryable := false                      # true while a parry would catch this enemy's punch
var is_stunned := false
var lunging := false
var next_lunge_msec := 0
var glow_root: Node3D                       # holds the ring and light; hidden unless a parryable attack is coming
var glow_fist: Node3D
var glow_elbow: Node3D
var glow_arm: MeshInstance3D                # second copy of the body that only draws the heat, so hit flashes keep working
var glow_arm_material: ShaderMaterial
var glow_wisps: GPUParticles3D
var glow_trail: Node3D
var glow_halo: MeshInstance3D
var glow_halo_material: StandardMaterial3D
var glow_light: OmniLight3D
var glow_time := 0.0
var glow_strength := 0.0                    # 0..1, ramps up through the wind-up
var recoil: HitRecoil                       # bends the upper body on hits and parries, over the animation
var strafe: StrafeTwist                     # turns the legs towards where it walks while it faces elsewhere
var walking_backward := false               # the circling walk is playing in reverse
var last_position := Vector3.INF
var circle_playback_set := false            # anim.speed_scale is matched to the circling speed right now

@onready var attack_timer: Timer = $AttackTimer
@onready var vision_area: Area3D = $VisionArea
@onready var attack_hitbox: Area3D = $Enemy_Model/Rig/Skeleton3D/RightHand/RightAttackHitbox
@onready var debug_sphere: MeshInstance3D = MeshInstance3D.new()


func _ready():
	super()
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))
	attack_hitbox.connect("body_entered", Callable(self, "_on_attack_hitbox_body_entered"))
	_build_left_hitbox()

	attack_animation_action = "Sword_Attack"
	attack_idle_animation = "Sword_Idle"
	_build_parry_glow()
	# Modifiers run in order: the strafe twist first, so hits still bend the body on top of it
	strafe = StrafeTwist.new()
	strafe.name = "StrafeTwist"
	$Enemy_Model/Rig/Skeleton3D.add_child(strafe)
	recoil = HitRecoil.new()
	recoil.name = "HitRecoil"
	$Enemy_Model/Rig/Skeleton3D.add_child(recoil)
	_roll_lunge_cooldown(0.5)

	#draw_debug_gizmos()


func get_state_definitions() -> Dictionary:
	return {
		"Idle": ENEMY_STATES.IdleState.new(self),
		"Chase": ENEMY_STATES.ChaseState.new(self),
		"Attack": ENEMY_STATES.AttackState.new(self),
		"AttackIdle": ENEMY_STATES.AttackIdleState.new(self),
		"Jump": JumpState.new(self),
		"Lunge": LungeState.new(self),
		"Stunned": StunnedState.new(self),
		"Dead": ENEMY_STATES.DeadState.new(self),
	}


func _on_body_entered(body: Node3D):
	if body == target and not _is_committed():
		change_state("Chase")


func _on_body_exited(body: Node3D):
	if body == target and not _is_committed() and not _within_leash():
		change_state("Idle")


func _physics_process(delta):
	super(delta)
	if state == states["Chase"] and not _within_leash():
		change_state("Idle")
	_update_attack_turn(delta)
	_update_strafe(delta)


# Tells the strafe twist how the enemy actually moved (avoidance included) and whether it is walking or running
func _update_strafe(delta: float) -> void:
	if strafe == null:
		return
	if last_position != Vector3.INF and delta > 0.0:
		strafe.world_velocity = strafe.world_velocity.lerp((global_position - last_position) / delta, 0.5)
	last_position = global_position
	var current := anim.current_animation
	strafe.walking = not destroyed and (current == RUN_ANIMATION or WAITING_CLIP_SPEEDS.has(current))
	# The waiting walk and jog keep pace with the ground; anything else plays at its normal speed again
	if WAITING_CLIP_SPEEDS.has(current):
		var pace: float = strafe.world_velocity.length() / WAITING_CLIP_SPEEDS[current]
		anim.speed_scale = clampf(pace, CIRCLE_PLAYBACK_RANGE.x, CIRCLE_PLAYBACK_RANGE.y)
		circle_playback_set = true
	elif circle_playback_set:
		anim.speed_scale = 1.0
		circle_playback_set = false


func _exit_tree() -> void:
	release_attack_slot()
	attack_token += 1   # a level restart can take it out of the tree mid punch: the running attack must stop


func can_start_attack() -> bool:
	return can_attack() and _claim_attack_slot()


# Every turn goes through here: walking into reach, the lunge, and taking one early on its own
func _claim_attack_slot() -> bool:
	if holds_attack_slot:
		return true
	if Time.get_ticks_msec() < next_turn_msec and _others_waiting():
		return false   # resting after its last turn while others wait for one
	attack_slot_holders = attack_slot_holders.filter(func(holder): return is_instance_valid(holder) and not holder.destroyed)
	if attack_slot_holders.size() >= MAX_ATTACKERS:
		return false
	attack_slot_holders.append(self)
	holds_attack_slot = true
	slot_held_time = 0.0
	return true


func release_attack_slot() -> void:
	if holds_attack_slot:
		attack_slot_holders.erase(self)
		holds_attack_slot = false
		rejoin_ring = true
		if is_inside_tree() and _others_waiting():
			# Rest on the ring a while before going again: the ones that have been waiting get in first
			var rest := attack_cooldown + randf_range(crowd_rest.x, crowd_rest.y)
			next_turn_msec = Time.get_ticks_msec() + int(rest * 1000.0)


func _update_attack_turn(delta: float) -> void:
	if destroyed or not is_instance_valid(target):
		return
	if holds_attack_slot and not is_attacking and state != states.get("Lunge"):
		slot_held_time += delta
		if slot_held_time > SLOT_HOLD_TIME:
			release_attack_slot()
			attack_timer.start(attack_cooldown)   # lets another enemy have a turn
	if state != states["Chase"]:
		return
	# Ready to strike, or nobody else wants a turn: take one (an enemy on its own never has to wait)
	if not holds_attack_slot and global_position.distance_to(target.global_position) <= engage_distance \
			and (can_attack() or not _others_waiting()):
		_claim_attack_slot()
	if _is_circling():
		_update_shuffle(delta)
	if _is_circling() or _is_pressing():
		_step_to_spot()
	_update_chase_animation()


# Waiting on its spot of the ring for a turn
func _is_circling() -> bool:
	return state == states["Chase"] and not holds_attack_slot and flank_assigned \
			and global_position.distance_to(target.global_position) <= flank_radius + 1.5


# Holds a turn but its attack is still cooling down: it waits just out of reach
func _is_pressing() -> bool:
	return state == states["Chase"] and holds_attack_slot and not can_attack() and not lunging


# Another melee enemy close by is waiting for a turn, so this one should give its up between attacks
func _others_waiting() -> bool:
	for other in get_tree().get_nodes_in_group("Enemy"):
		if other == self or not other is EnemyHorde or other.destroyed or other.holds_attack_slot:
			continue
		if not other.is_inside_tree():   # already on its way out (the level is unloading)
			continue
		if other.state == other.states.get("Chase") and is_instance_valid(other.target) \
				and other.global_position.distance_to(other.target.global_position) <= engage_distance:
			return true
	return false


# Every so often a waiting enemy shuffles a few steps round the ring, sometimes turning back, sometimes stepping in
# or out a little; in between it stands its ground (the wait only counts down once it has got to its spot)
func _update_shuffle(delta: float) -> void:
	if chase_speed() > 0.0:
		return
	shuffle_timer -= delta
	if shuffle_timer > 0.0:
		return
	shuffle_timer = randf_range(shuffle_interval.x, shuffle_interval.y)
	if randf() < 0.35:
		circle_direction = -circle_direction
	flank_angle += circle_direction * randf_range(shuffle_angle.x, shuffle_angle.y)
	flank_radius = clampf(flank_radius + randf_range(-0.8, 0.8), ring_radius_min, ring_radius_max)


# Runs to where it is going. Waiting for a turn it stands on guard, and walks when it shuffles or steps in (in
# reverse while backing away; StrafeTwist turns the legs to match). A hit reaction playing is left to finish.
func _update_chase_animation() -> void:
	var wanted := RUN_ANIMATION
	if _is_circling() or _is_pressing():
		var speed := chase_speed()
		var still := speed == 0.0 and strafe != null and strafe.world_velocity.length() < STAND_SPEED
		if still:
			wanted = attack_idle_animation
		else:
			wanted = REPOSITION_ANIMATION if speed > waiting_walk_speed else CIRCLE_ANIMATION
	var backward := WAITING_CLIP_SPEEDS.has(wanted) and strafe != null and strafe.backward
	var current := anim.current_animation
	# Nothing playing counts too (a reversed walk can run off its start and stop)
	var on_foot := current == "" or current == RUN_ANIMATION or current == attack_idle_animation \
			or WAITING_CLIP_SPEEDS.has(current)
	if on_foot and anim.has_animation(wanted) and (current != wanted or backward != walking_backward):
		if backward:
			anim.play_backwards(wanted, 0.2)
		else:
			anim.play(wanted, 0.2)
		walking_backward = backward
	elif not WAITING_CLIP_SPEEDS.has(current):
		walking_backward = false


func _assign_flank() -> void:
	flank_assigned = true
	var from_target := global_position - target.global_position
	flank_angle = atan2(from_target.x, from_target.z) + randf_range(-FLANK_SPREAD, FLANK_SPREAD)
	flank_radius = randf_range(ring_radius_min, ring_radius_max)
	circle_direction = 1.0 if randf() < 0.5 else -1.0


func chase_destination() -> Vector3:
	var goal := target.global_position
	if holds_attack_slot:
		return _press_point() if _is_pressing() else goal
	if not flank_assigned:
		_assign_flank()
	elif rejoin_ring:
		# Back from a turn: a spot on the ring on its own side, not wherever it was waiting before (which could
		# be on the far side, through the player and the rest of the crowd)
		var from_target := global_position - goal
		flank_angle = atan2(from_target.x, from_target.z) + randf_range(-0.35, 0.35)
		flank_radius = randf_range(ring_radius_min, ring_radius_min + 1.0)
		shuffle_timer = randf_range(shuffle_interval.x, shuffle_interval.y)
	rejoin_ring = false
	if absf(goal.y - global_position.y) > FLANK_MAX_HEIGHT_GAP:
		return goal
	var point := goal + Vector3(sin(flank_angle), 0.0, cos(flank_angle)) * flank_radius
	# A spot behind a wall could be anywhere on the far side: stay on the player's side of it
	var query := PhysicsRayQueryParameters3D.create(goal + Vector3.UP, point + Vector3.UP, PhysicsLayers.ENVIRONMENT)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var wall: Vector3 = hit["position"]
		return Vector3(wall.x, goal.y, wall.z) - (point - goal).normalized() * FLANK_WALL_MARGIN
	return point


# The navigation agent counts a destination as reached a metre short of it, which leaves a waiting enemy standing in
# the wrong place (in the player's face, when pressing in): it walks the last bit straight there itself
func _step_to_spot() -> void:
	if not nav.is_navigation_finished():
		return
	var spot := chase_destination()
	var to_spot := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if to_spot.length() < ARRIVED:
		return
	velocity = to_spot.normalized() * chase_speed()
	move_and_slide()


# Just outside its reach, on its own side of the player
func _press_point() -> Vector3:
	var goal := target.global_position
	var away := global_position - goal
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else -target.global_basis.z
	return goal + away * (melee_range + press_gap)


func chase_speed() -> float:
	if not (_is_circling() or _is_pressing()):
		return movement_speed
	var spot := chase_destination()
	var gap := Vector2(spot.x - global_position.x, spot.z - global_position.z).length()
	if gap < ARRIVED:
		return 0.0   # there: stand on guard
	return reposition_speed if gap > REPOSITION_GAP else waiting_walk_speed


func chase_faces_target() -> bool:
	return _is_circling() or _is_pressing()


# Waiting enemies set their own pace to their spot (and stop there), so the chase's slow-down near a waypoint, which
# would have them creep the last two metres, is skipped
func chase_eases_into_waypoints() -> bool:
	return not (_is_circling() or _is_pressing())


func _within_leash() -> bool:
	return is_instance_valid(target) and global_position.distance_to(target.global_position) <= chase_leash


# These moves finish on their own whatever the vision area reports (cutting a jump short would leave it in mid-air)
func _is_committed() -> bool:
	return state in [states.get("Jump"), states.get("Lunge"), states.get("Stunned"), states.get("Dodge")]


# Where a committed move goes when it ends: the player may have left its vision meanwhile
func resume_after_move() -> void:
	change_state("Chase" if _within_leash() else "Idle")


func is_in_attack_range() -> bool:
	if not target:
		return false
	return global_position.distance_to(target.global_position) <= melee_range


func can_attack() -> bool:
	# Ready to attack if cooldown finished
	return attack_timer.is_stopped()


func perform_attack() -> void:
	if lunging:
		_perform_heavy_attack()
	else:
		_perform_combo()


# The single swing used by the lunge: Sword_Attack with its one long damage window (this is what a parry catches)
func _perform_heavy_attack() -> void:
	is_attacking = true
	hit_damage_scale = 1.0
	var token := attack_token

	# Play the attack animation
	anim.play(attack_animation_action)

	# Play hit sounds
	audio_player.play("assets/audio/sfx/enemies/Enemy_Hit1.wav, \
					   assets/audio/sfx/enemies/Enemy_Hit2.wav, \
					   assets/audio/sfx/enemies/Enemy_Hit3.wav")

	# Wait until attack animation reaches "damage window start". A lunge's punch can be parried only right as it is
	# about to land: from parry_lead before the damage window until it connects (or parry_late after, if it misses).
	var lead := minf(parry_lead, damage_window_start) if lunging else 0.0
	if not await _wait_attack(damage_window_start - lead, token):
		return  # parried (or otherwise cancelled) before the punch landed
	if lunging:
		_open_parry_window()
		if not await _wait_attack(lead, token):
			return

	# Reset hit flag RIGHT before enabling hitbox (not at start of function)
	hit_done = false
	attack_hitbox.monitoring = true
	if parryable:
		_close_parry_window_after(parry_late, token)

	# Calculate damage window duration
	var damage_duration = max(0.0, damage_window_end - damage_window_start)
	var still_attacking := await _wait_attack(damage_duration, token)
	attack_hitbox.monitoring = false
	if not still_attacking:
		return

	# Wait until the animation finishes fully
	var remaining := (anim.current_animation_length - anim.current_animation_position) / maxf(anim.speed_scale, 0.01)
	if not await _wait_attack(maxf(remaining, 0.0), token):
		return

	# Start cooldown
	attack_timer.start(attack_cooldown)

	# Allow future attacks
	is_attacking = false
	release_attack_slot()


# Waits for the given time and says whether the attack carries on: false once it was cancelled (parry, death).
# The wait is a timer owned by this enemy, so if the enemy is freed meanwhile the wait is dropped with it instead
# of resuming this function on a freed object.
func _wait_attack(seconds: float, token: int) -> bool:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(maxf(seconds, 0.001))
	await timer.timeout
	timer.queue_free()
	return token == attack_token


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if body == target and not hit_done:
		parryable = false   # it has connected: too late to parry
		# A lunge is not stopped by a block: the player is shoved out of its way and takes the reduced damage
		if lunging and body.get("shield_blocking") == true:
			_shove_blocking_player(body)
		_report_block(body)
		if body.has_method("damage"):
			body.damage(damage_to_player * hit_damage_scale, true)

		hit_done = true


# The player's shield sounds off when it takes a blow (only while it is held up)
func _report_block(player: Node3D) -> void:
	var player_shield = player.get("offhand_shield")
	if player_shield != null and player_shield.has_method("on_melee_blocked"):
		player_shield.on_melee_blocked(self)


func _shove_blocking_player(player: Node3D) -> void:
	var heading := player.global_position - global_position
	heading.y = 0.0
	heading = heading.normalized() if heading.length() > 0.001 else -global_basis.z
	var side := heading.cross(Vector3.UP)
	if randf() < 0.5:
		side = -side
	# Prefer a side with room to be shoved into
	var chest := player.global_position + Vector3.UP
	for candidate in [side, -side]:
		var query := PhysicsRayQueryParameters3D.create(chest, chest + candidate * lunge_shove_clearance)
		query.exclude = [player, self]
		query.collision_mask = 1 | 2
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			side = candidate
			break
	if player.has_method("apply_push"):
		player.apply_push(side * lunge_shove_speed + heading * lunge_shove_speed * 0.2)
	if player.has_method("apply_camera_kick"):
		player.apply_camera_kick(0.05, randf_range(-0.03, 0.03))
	var player_shield = player.get("offhand_shield")
	if player_shield != null and player_shield.has_method("on_block_hit"):
		player_shield.on_block_hit(global_position.lerp(player.global_position, 0.7) + Vector3.UP * 1.2)


# ---------------------------
# Punch combo
# ---------------------------
# The left fist needs a hitbox of its own: a copy of the right one, on the left hand
func _build_left_hitbox() -> void:
	var left_hand := get_node_or_null("Enemy_Model/Rig/Skeleton3D/LeftHand")
	if left_hand == null:
		return
	left_hitbox = attack_hitbox.duplicate() as Area3D
	left_hitbox.name = "LeftAttackHitbox"
	left_hitbox.monitoring = false
	left_hand.add_child(left_hitbox)
	var callback := Callable(self, "_on_attack_hitbox_body_entered")
	if not left_hitbox.body_entered.is_connected(callback):
		left_hitbox.body_entered.connect(callback)


func _hitbox_for(hand: String) -> Area3D:
	return left_hitbox if hand == "L" and left_hitbox != null else attack_hitbox


func _perform_combo() -> void:
	is_attacking = true
	var token := attack_token
	var first := true
	for punch in COMBO:
		# The follow-up only comes if the player is still close
		if not first and (not is_instance_valid(target) or global_position.distance_to(target.global_position) > combo_chain_range):
			break
		first = false
		anim.play(punch["animation"])
		audio_player.play("assets/audio/sfx/enemies/Enemy_Hit1.wav, 						   assets/audio/sfx/enemies/Enemy_Hit2.wav, 						   assets/audio/sfx/enemies/Enemy_Hit3.wav")

		var hits: Array = punch["hits"]
		var active := -1                      # index of the hit whose hitbox is live right now
		var elapsed := 0.0
		while elapsed < punch["length"]:
			await get_tree().physics_frame
			if token != attack_token:
				return  # cancelled (death); whoever cancelled it has cleaned up
			var step := get_physics_process_delta_time()
			elapsed += step
			face_target(step, 1.0)
			_combo_step_in()

			var wanted := -1
			for i in hits.size():
				if elapsed >= hits[i]["start"] and elapsed < hits[i]["end"]:
					wanted = i
					break
			if wanted != active:
				if active >= 0:
					_hitbox_for(hits[active]["hand"]).monitoring = false
				if wanted >= 0:
					hit_done = false  # every punch can land once
					hit_damage_scale = hits[wanted]["damage"]
					_hitbox_for(hits[wanted]["hand"]).monitoring = true
				active = wanted
		if active >= 0:
			_hitbox_for(hits[active]["hand"]).monitoring = false

	velocity = Vector3.ZERO
	attack_timer.start(attack_cooldown)
	is_attacking = false
	release_attack_slot()


func _combo_step_in() -> void:
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > combo_step_distance:
		velocity = to_target.normalized() * combo_step_speed
		move_and_slide()
	else:
		velocity = Vector3.ZERO


# A lunging, jumping or dazed enemy is not interrupted by a flinch
func _can_play_hit_reaction() -> bool:
	return not lunging and not is_stunned and state != states.get("Jump") and super()


func _can_jump() -> bool:
	return jump_enabled and not lunging and not is_stunned and super()


# ---------------------------
# Lunge
# ---------------------------
func _roll_lunge_cooldown(min_seconds := -1.0) -> void:
	var seconds := randf_range(lunge_cooldown_min, lunge_cooldown_max) if min_seconds < 0.0 else randf_range(min_seconds, lunge_cooldown_max)
	next_lunge_msec = Time.get_ticks_msec() + int(seconds * 1000.0)


# Asked by the chase state every frame: lunge when closing in from range, with a clear path and not too many at once
func should_lunge() -> bool:
	if not lunge_enabled or is_attacking or is_stunned or not is_instance_valid(target):
		return false
	if Time.get_ticks_msec() < next_lunge_msec:
		return false
	var distance := global_position.distance_to(target.global_position)
	if distance < lunge_min_range or distance > lunge_max_range:
		return false
	if not _path_reaches_target(distance):
		return false  # across a gap with no way over: the dash would carry it out over thin air
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP)
	query.exclude = [self]
	query.collision_mask = 1 | 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") != target:
		return false
	var active := 0
	for other in get_tree().get_nodes_in_group("Enemy"):
		if other != self and other.get("lunging") == true:
			active += 1
	return active < MAX_SIMULTANEOUS_LUNGES and _claim_attack_slot()


# True when the agent's current path actually gets to the target without a long detour (a jump link counts)
func _path_reaches_target(straight_distance: float) -> bool:
	var path := nav.get_current_navigation_path()
	if path.size() < 2:
		return true  # no path yet: the chase will sort it out
	var length := 0.0
	for i in path.size() - 1:
		length += Vector2(path[i].x - path[i + 1].x, path[i].z - path[i + 1].z).length()
	var end := path[path.size() - 1]
	var gap_to_target := Vector2(end.x - target.global_position.x, end.z - target.global_position.z).length()
	return gap_to_target < 2.5 and length <= straight_distance * 1.6 + 2.0


# Turns towards the target on the spot (the model faces +Z, hence the extra half turn)
func face_target(delta: float, speed_multiplier := 2.0) -> void:
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return
	var target_basis := Basis.looking_at(to_target.normalized(), Vector3.UP).rotated(Vector3.UP, deg_to_rad(180))
	global_transform.basis = global_transform.basis.slerp(target_basis, clampf(delta * rotation_speed * speed_multiplier, 0.0, 1.0))


func _on_shoved() -> void:
	attack_token += 1
	parryable = false
	is_attacking = false
	attack_hitbox.set_deferred("monitoring", false)
	if left_hitbox:
		left_hitbox.set_deferred("monitoring", false)
	release_attack_slot()
	if state == states.get("Lunge") or state == states.get("Attack"):
		change_state("Chase")


# Called by the player's shield when a parry catches the punch: cancels the attack and stuns the enemy
func on_parried() -> void:
	if recoil and is_instance_valid(target):
		recoil.parry(global_position - target.global_position, parry_stun_time)
	attack_token += 1
	parryable = false
	hit_done = true
	attack_hitbox.set_deferred("monitoring", false)
	is_attacking = false
	attack_timer.start(attack_cooldown)
	release_attack_slot()
	change_state("Stunned")


func damage(amount: float, multiplier: float = 1.0):
	super(amount, multiplier * (parry_stun_damage_multiplier if is_stunned else 1.0))


# Hits bend the body where they land (HitRecoil) instead of jolting the whole model. Mid-attack they still show,
# a little less, without stopping the swing; the killing shot throws it too.
func flinch(world_point: Vector3, strength := 1.0) -> void:
	if recoil == null:
		super(world_point, strength)
		return
	if strength <= 0.0:
		return
	var from_position := global_position + global_basis.z
	if GlobalVariables.player and is_instance_valid(GlobalVariables.player):
		from_position = GlobalVariables.player.global_position
	recoil.hit(world_point, world_point - from_position, strength * (0.6 if is_attacking else 1.0))


# ---------------------------
# Yellow fist aura: the sign that this punch can be parried
# ---------------------------
# The arm heats up from the knuckles, wisps stream off the fist, a ribbon follows the swing and a ring closes in on the
# fist. The ring lands as the parry window opens, and a star glint marks that moment.
func _build_parry_glow() -> void:
	var hand := get_node_or_null("Enemy_Model/Rig/Skeleton3D/RightHand")
	if hand == null:
		return
	glow_elbow = get_node_or_null("Enemy_Model/Rig/Skeleton3D/RightForearm")
	glow_fist = Node3D.new()
	glow_fist.position = FIST_OFFSET
	hand.add_child(glow_fist)
	glow_root = Node3D.new()
	glow_root.visible = false
	glow_fist.add_child(glow_root)

	if model and glow_elbow:
		glow_arm_material = ShaderMaterial.new()
		glow_arm_material.shader = ARM_HEAT_SHADER
		glow_arm = MeshInstance3D.new()
		glow_arm.mesh = model.mesh
		glow_arm.skin = model.skin
		glow_arm.material_override = glow_arm_material
		glow_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow_arm.visible = false
		model.get_parent().add_child(glow_arm)
		glow_arm.transform = model.transform
		glow_arm.skeleton = model.skeleton

	# Outside glow_root: when the punch ends these stop emitting and fade on their own
	glow_wisps = ParryFx.make_wisps(WISP_RADIUS)
	glow_wisps.emitting = false
	glow_fist.add_child(glow_wisps)
	glow_trail = GlowTrail.new()
	glow_trail.source = glow_fist
	glow_trail.active = false
	glow_trail.head_color = Color(1.0, 0.75, 0.0)
	glow_trail.tail_color = Color(1.0, 0.35, 0.0)
	glow_trail.max_points = 12
	glow_trail.spacing = 0.12
	glow_trail.width = 0.08
	glow_fist.add_child(glow_trail)

	# A soft ring that always faces the camera, with an empty centre so it never covers the fist
	var ring := Gradient.new()
	ring.offsets = PackedFloat32Array([0.0, 0.66, 0.74, 0.78, 0.86])
	ring.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = ring
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	glow_halo_material = StandardMaterial3D.new()
	glow_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_halo_material.billboard_keep_scale = true
	glow_halo_material.albedo_texture = texture
	glow_halo_material.albedo_color = Color(AURA_COLOR * 2.0, 0.0)
	glow_halo_material.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	glow_halo = MeshInstance3D.new()
	glow_halo.mesh = quad
	glow_halo.material_override = glow_halo_material
	glow_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_root.add_child(glow_halo)

	glow_light = OmniLight3D.new()
	glow_light.light_color = GLOW_LIGHT_COLOR
	glow_light.omni_range = 2.0
	glow_light.light_energy = 0.0
	glow_light.shadow_enabled = false
	glow_root.add_child(glow_light)


func set_parry_glow(enabled: bool) -> void:
	if glow_root == null:
		return
	glow_root.visible = enabled
	glow_halo.visible = enabled
	glow_wisps.emitting = enabled
	glow_trail.active = enabled
	if glow_arm:
		glow_arm.visible = enabled
	if not enabled:
		glow_strength = 0.0


# The punch can be parried from now on: the ring has landed, and the glint says so
# Ends a parry window a moment after the blow should have landed, if it hasn't been parried or landed by then
func _close_parry_window_after(seconds: float, token: int) -> void:
	await get_tree().create_timer(seconds, false).timeout
	if token == attack_token:
		parryable = false


func _open_parry_window() -> void:
	parryable = true
	glow_strength = 1.0
	if glow_root == null:
		return
	glow_halo.visible = false
	ParryFx.play_star_glint(glow_fist, FIST_GLINT_SIZE)


func _process(delta: float) -> void:
	if glow_root == null or not glow_root.visible:
		return
	glow_time += delta
	# Builds up through the wind-up and pulses faster and brighter as the punch gets closer
	var pulse := 1.0 + 0.12 * sin(glow_time * (12.0 + glow_strength * 10.0))
	glow_wisps.amount_ratio = lerpf(0.3, 1.0, glow_strength)
	glow_halo.scale = Vector3.ONE * lerpf(RING_START_SCALE, RING_END_SCALE, glow_strength * glow_strength)
	glow_halo_material.albedo_color = Color(AURA_COLOR * 1.6, 0.15 + 0.6 * glow_strength)
	glow_light.light_energy = 1.0 * glow_strength
	if glow_arm_material:
		glow_arm_material.set_shader_parameter("fist_point", glow_fist.global_position)
		glow_arm_material.set_shader_parameter("elbow_point", glow_elbow.global_position)
		glow_arm_material.set_shader_parameter("reach", lerpf(0.15, 1.0, glow_strength))
		glow_arm_material.set_shader_parameter("intensity", lerpf(0.4, 0.8, glow_strength) * pulse)


func draw_debug_gizmos():
	if OS.is_debug_build() and debug:  # only show in debug mode
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = vision_range
		sphere_mesh.radial_segments = 24
		sphere_mesh.rings = 16
		debug_sphere.mesh = sphere_mesh

		# Transparent material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 1, 0, 0.2)  # semi-transparent green
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_sphere.material_override = mat

		# Attach sphere to vision_area so it moves with the enemy
		vision_area.add_child(debug_sphere)
		debug_sphere.position = Vector3.ZERO


func _on_attack_cooldown_timeout() -> void:
	hit_done = false


# ---------------------------
# States
# ---------------------------
# Jumps a gap bridged by a NavigationLink3D: an arc from where the agent reached the link to its far end.
class JumpState:
	var enemy
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var duration := 0.6
	var apex := 1.0
	var elapsed := 0.0
	var landing := false
	var landing_left := 0.0

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		var link: Dictionary = enemy.pending_link
		var entry: Vector3 = link.get("link_entry_position", enemy.global_position)
		var exit_point: Vector3 = link.get("link_exit_position", enemy.global_position)
		start = enemy.global_position
		# The enemy stands a little off the navigation mesh's height; keep that offset on the far side
		end = exit_point + Vector3(0.0, start.y - entry.y, 0.0)
		var run := Vector2(end.x - start.x, end.z - start.z).length()
		duration = clampf(run / enemy.jump_speed, enemy.jump_min_time, enemy.jump_max_time)
		apex = maxf(enemy.jump_height, (end.y - start.y) + 0.6)
		elapsed = 0.0
		landing = false
		# Jump_Start is a whole hop (crouch, spring, legs tucked, legs lowered): fit it to the flight
		enemy.anim.play("Jump_Start")
		enemy.anim.speed_scale = enemy.anim.get_animation("Jump_Start").length / (duration * 0.95)

	func update(delta):
		enemy.should_move = false  # nothing else may drive the body while it jumps
		if landing:
			enemy.face_target(delta, 2.0)
			landing_left -= delta
			if landing_left <= 0.0:
				enemy.resume_after_move()
			return
		elapsed += delta
		var t := clampf(elapsed / duration, 0.0, 1.0)
		var position := start.lerp(end, t)
		position.y = lerpf(start.y, end.y, t) + 4.0 * apex * t * (1.0 - t)
		enemy.global_position = position
		_face(end, delta)
		if t >= 1.0:
			enemy.global_position = end
			landing = true
			landing_left = enemy.jump_land_time
			enemy.anim.play("Jump_Land")
			enemy.anim.speed_scale = 2.2

	func _face(point: Vector3, delta: float) -> void:
		var to_point: Vector3 = point - enemy.global_position
		to_point.y = 0.0
		if to_point.length() < 0.05:
			return
		var target_basis := Basis.looking_at(to_point.normalized(), Vector3.UP).rotated(Vector3.UP, deg_to_rad(180))
		enemy.global_transform.basis = enemy.global_transform.basis.slerp(target_basis, clampf(delta * 12.0, 0.0, 1.0))

	func exit():
		enemy.anim.speed_scale = 1.0
		enemy.velocity = Vector3.ZERO
		enemy.jump_ready_msec = Time.get_ticks_msec() + 700  # the agent may still be 'on' the link it just crossed


# Crouch with a charging fist, dash at the player, then the normal punch as the finishing blow.
class LungeState:
	enum Phase { WINDUP, DASH, STRIKE }

	var enemy
	var phase := Phase.WINDUP
	var timer := 0.0
	var phase_time := 0.0

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		enemy.lunging = true
		enemy.glow_time = 0.0
		enemy.glow_strength = 0.0
		enemy.set_parry_glow(true)
		phase = Phase.WINDUP
		timer = enemy.lunge_windup
		phase_time = 0.0
		var windup_animation: String = enemy.lunge_windup_animation
		enemy.anim.play(windup_animation if enemy.anim.has_animation(windup_animation) else "Idle")

	func update(delta):
		if not is_instance_valid(enemy.target):
			enemy.change_state("Idle")
			return
		match phase:
			Phase.WINDUP:
				enemy.face_target(delta, 4.0)
				timer -= delta
				enemy.glow_strength = clampf(1.0 - timer / maxf(enemy.lunge_windup, 0.01), 0.0, 1.0)
				if timer <= 0.0:
					phase = Phase.DASH
					timer = enemy.lunge_dash_time
					# Fully charged, but the parry window waits for the punch itself (_perform_heavy_attack)
					enemy.glow_strength = 1.0
					enemy.anim.play("Sprint")
					enemy.anim.speed_scale = 1.4
			Phase.DASH:
				enemy.face_target(delta, 4.0)
				var to_target: Vector3 = enemy.target.global_position - enemy.global_position
				to_target.y = 0.0
				timer -= delta
				if to_target.length() <= enemy.lunge_strike_range or timer <= 0.0:
					enemy.anim.speed_scale = 1.0
					enemy.velocity = Vector3.ZERO
					phase = Phase.STRIKE
					enemy.perform_attack()  # the normal punch: its damage window is what a parry has to catch
					return
				enemy.velocity = to_target.normalized() * enemy.lunge_speed
				enemy.move_and_slide()
			Phase.STRIKE:
				enemy.face_target(delta, 2.0)
				# The punch carries the enemy the last bit of the way, so it actually connects
				phase_time += delta
				var to_target: Vector3 = enemy.target.global_position - enemy.global_position
				to_target.y = 0.0
				if phase_time < enemy.lunge_follow_through and to_target.length() > enemy.lunge_reach:
					enemy.velocity = to_target.normalized() * enemy.lunge_speed * 0.5
					enemy.move_and_slide()
				if not enemy.is_attacking:
					enemy.resume_after_move()

	func exit():
		enemy.lunging = false
		enemy.parryable = false
		enemy.set_parry_glow(false)
		if not enemy.is_attacking:
			enemy.release_attack_slot()
		enemy.anim.speed_scale = 1.0
		enemy.velocity = Vector3.ZERO
		enemy._roll_lunge_cooldown()


# Dazed after a parry: knocked back, then stands up and carries on. Takes extra damage while dazed.
class StunnedState:
	var enemy
	var timer := 0.0
	var knockback := Vector3.ZERO

	func _init(e):
		enemy = e

	func enter():
		enemy.is_stunned = true
		enemy.should_move = false
		timer = enemy.parry_stun_time
		var away: Vector3 = enemy.global_position - enemy.target.global_position if is_instance_valid(enemy.target) else -enemy.global_basis.z
		away.y = 0.0
		knockback = away.normalized() * 7.0
		enemy.anim.play("Hit_Chest")
		enemy.anim.queue("Idle")

	func update(delta):
		timer -= delta
		knockback = knockback.move_toward(Vector3.ZERO, 22.0 * delta)
		enemy.velocity = knockback
		enemy.move_and_slide()
		if timer <= 0.0:
			enemy.resume_after_move()

	func exit():
		enemy.is_stunned = false
		enemy.velocity = Vector3.ZERO
