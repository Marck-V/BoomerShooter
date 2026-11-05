extends EnemyHorde
class_name EnemySwordsman

# A melee enemy with a sword. It shares the horde enemy's body, chase, crowd turns, gap jumps and parry stun.
#
# Up close it swings a three-hit combo, Sword_Regular A, B and C. It tracks the player through each wind-up, then
# commits to the swing, so stepping or dashing out of its path as it starts dodges it. A player who backs off between
# strikes is chased (a short sprint) and the combo carries on; only getting clean away (out of combo_pursuit_range,
# or outrunning the chase) ends it early, with that strike's recovery. A finisher (C) that cuts only air leaves it
# off balance for whiff_recovery, an opening to hit back. One strike of every combo, A or C picked at random,
# glows yellow and can be parried (A's quick wind-up slows down when it's that one, so there is time to read it). B is never parryable: the
# blade flashes red before it. Closing in from range it opens with Sword_Dash: a red flash, then a dash and a slash
# that can't be parried (a block gets the player shoved aside, as with the horde enemy's lunge).
#
# The sword animations come from UAL2_Standard.glb, copied onto this rig by tools/assetgen/retarget_ual2_sword.gd.
# The sword itself is built here, in the right hand.

const SWORD_LIBRARY: AnimationLibrary = preload("res://models/enemies/sword_animations.res")
const LIBRARY := "sword"

@export_group("Sword")
@export var parry_both_a_and_c := false     # false: one of A or C per combo is parryable; true: both are
@export var parryable_windup_slowdown := 0.45   # speed of A's wind-up when it's the parryable one, so the glow can be read
@export var dash_damage := 0.5              # share of damage_to_player
@export var dash_strike_distance := 1.5     # the dash stops this far from the player
@export var dash_windup_speed := 0.3        # speed of the dash's first frames, the red-flash wind-up
@export var hit_knockback := 6.0            # pushes the player back when a strike lands
@export var combo_pursuit_range := 6.5      # backing off mid-combo: within this he runs after you and carries on
@export var combo_pursuit_speed := 8.0      # (the player walks at 10, so a steady retreat still gets away)
@export var combo_pursuit_time := 0.9       # gives up the chase after this long
@export var whiff_recovery := 0.9           # a final strike that cuts only air leaves him off balance this long

# Times are seconds into each clip, read from where the blade tip moves fastest in front of the body.
# windup: the part before the swing; hit: when the blade can hurt; end: where it cuts to the next move.
# slow_when_parryable: A's wind-up is too quick to read the yellow glow, so it slows down when A is the parryable
# strike. C's twirl is long enough at full speed.
const STRIKES := {
	"A": {"animation": "Sword_Regular_A", "recovery": "Sword_Regular_A_Rec", "windup": 0.17, "hit": [0.19, 0.33], "end": 0.43, "damage": 0.35, "slow_when_parryable": true},
	"B": {"animation": "Sword_Regular_B", "recovery": "Sword_Regular_B_Rec", "windup": 0.2, "hit": [0.21, 0.32], "end": 0.53, "damage": 0.35},
	"C": {"animation": "Sword_Regular_C", "recovery": "", "windup": 0.55, "hit": [0.59, 0.74], "end": 1.45, "damage": 0.6},
}
const COMBO_ORDER := ["A", "B", "C"]
const DASH := {"animation": "Sword_Dash", "windup": 0.1, "move": [0.06, 0.33], "hit": [0.27, 0.4], "end": 0.95}

# The sword, in the right hand bone's space: the middle of the closed fingers, and the way the blade comes out
# of the fist (from the little finger past the index), both measured by the retarget tool
const GRIP := Vector3(-0.04, 0.125, -0.005)
const BLADE_AXIS := Vector3(-0.0055, 0.1677, 0.9858)
const BLADE_START := 0.12                   # along the blade from the grip: the guard
const BLADE_LENGTH := 0.85
const TIP := BLADE_START + BLADE_LENGTH + 0.1
const PLAYER_HIT_RADIUS := 0.45
const PLAYER_LOW := 0.2                     # the player's body, from this high above its origin...
const PLAYER_HIGH := 1.7                    # ...to this

const PARRY_COLOR := Color(1.0, 0.8, 0.15)  # yellow: parryable
const DANGER_COLOR := Color(1.0, 0.1, 0.04) # red: not parryable
const STREAK_LEAD := 0.04                   # the red streak shows from this long before the hit window...
const STREAK_TAIL := 0.04                   # ...to this long after it (seconds into the clip)

var sword: Node3D
var streak: SwordStreak                     # red motion streak behind the blade on the attacks that can't be parried
var blade_material: StandardMaterial3D
var blade_glow_tween: Tween
var last_tip := Vector3.INF
var last_mid := Vector3.INF


func _ready():
	super()
	anim.add_animation_library(LIBRARY, SWORD_LIBRARY)
	attack_idle_animation = "Sword_Idle"
	_build_sword()
	_hold_grip()
	streak = SwordStreak.new()
	streak.name = "SwordStreak"
	streak.color = Color(1.0, 0.05, 0.02)    # the blade's red, a touch deeper so the added glow stays red
	streak.blade = func() -> Array: return [blade_points()[0], blade_points()[2]]
	add_child(streak)
	# The horde enemy's glow belongs on a fist: move it to the blade, without the arm heat
	if glow_fist:
		glow_fist.reparent(sword, false)
		glow_fist.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, BLADE_START + BLADE_LENGTH * 0.75, 0.0))
	if glow_arm:
		glow_arm.queue_free()
		glow_arm = null
		glow_arm_material = null
	next_lunge_msec = 0   # the first approach from range opens with the dash


func get_state_definitions() -> Dictionary:
	var definitions := super()
	definitions["Idle"] = SwordIdleState.new(self)
	definitions["Lunge"] = SwordDashState.new(self)
	definitions["Stunned"] = SwordStunnedState.new(self)
	return definitions


func clip(animation: String) -> String:
	return "%s/%s" % [LIBRARY, animation]


# ---------------------------
# The sword
# ---------------------------
# Blade along the sword node's +Y, its edge facing the way the knuckles point
func _build_sword() -> void:
	var hand: Node3D = $Enemy_Model/Rig/Skeleton3D/RightHand
	var y := BLADE_AXIS.normalized()
	var x := (Vector3.UP - y * y.dot(Vector3.UP)).normalized()
	sword = Node3D.new()
	sword.name = "Sword"
	hand.add_child(sword)
	sword.transform = Transform3D(Basis(x, y, x.cross(y)), GRIP)

	blade_material = StandardMaterial3D.new()
	# Not too mirror-like: a dark level would leave a fully metallic blade nearly black
	blade_material.albedo_color = Color(0.85, 0.88, 0.92)
	blade_material.metallic = 0.45
	blade_material.roughness = 0.3
	blade_material.rim_enabled = true
	blade_material.rim = 0.6
	blade_material.emission_enabled = true
	blade_material.emission = PARRY_COLOR
	blade_material.emission_energy_multiplier = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.18, 0.14, 0.12)
	dark.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.7, 0.55, 0.25)
	brass.metallic = 0.8
	brass.roughness = 0.4

	var blade := BoxMesh.new()
	blade.size = Vector3(0.055, BLADE_LENGTH, 0.012)
	_add_part(blade, blade_material, Vector3(0.0, BLADE_START + BLADE_LENGTH * 0.5, 0.0))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.055, 0.1, 0.012)
	_add_part(tip, blade_material, Vector3(0.0, BLADE_START + BLADE_LENGTH + 0.05, 0.0))
	var guard := BoxMesh.new()
	guard.size = Vector3(0.2, 0.03, 0.04)
	_add_part(guard, brass, Vector3(0.0, BLADE_START - 0.015, 0.0))
	var grip := CylinderMesh.new()
	grip.top_radius = 0.018
	grip.bottom_radius = 0.018
	grip.height = 0.2
	_add_part(grip, dark, Vector3(0.0, 0.0, 0.0))
	var pommel := SphereMesh.new()
	pommel.radius = 0.03
	pommel.height = 0.06
	_add_part(pommel, brass, Vector3(0.0, -0.11, 0.0))


func _add_part(mesh: Mesh, material: Material, at: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	sword.add_child(part)


# The blade, guard to tip, in the world
func blade_points() -> Array:
	return [sword.to_global(Vector3(0.0, BLADE_START, 0.0)), sword.to_global(Vector3(0.0, BLADE_START + BLADE_LENGTH * 0.5, 0.0)),
			sword.to_global(Vector3(0.0, TIP, 0.0))]


# Lights the blade up: yellow when the strike can be parried, red when it can't. 0 turns it off.
func set_blade_glow(color: Color, energy: float, seconds := 0.12) -> void:
	if blade_glow_tween and blade_glow_tween.is_valid():
		blade_glow_tween.kill()
	if energy > 0.0:
		blade_material.emission = color
	blade_glow_tween = create_tween()
	blade_glow_tween.tween_property(blade_material, "emission_energy_multiplier", energy, seconds)


# The UAL1 clips (idle, run, death) open the hand; the sword ones close it on the grip. Keeps it closed in all of them.
func _hold_grip() -> void:
	var skeleton: Skeleton3D = $Enemy_Model/Rig/Skeleton3D
	var source := SWORD_LIBRARY.get_animation("Sword_Regular_A")
	var hold := GripHold.new()
	for track in source.get_track_count():
		var bone := String(source.track_get_path(track).get_subname(0))
		if source.track_get_type(track) == Animation.TYPE_ROTATION_3D and bone.ends_with(".R") \
				and (bone.begins_with("DEF-f_") or bone.begins_with("DEF-thumb")):
			hold.rotations[skeleton.find_bone(bone)] = source.rotation_track_interpolate(track, 0.0)
	skeleton.add_child(hold)


class GripHold extends SkeletonModifier3D:
	var rotations := {}   # bone index -> its rotation in the grip

	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		for bone in rotations:
			skeleton.set_bone_pose_rotation(bone, rotations[bone])


# ---------------------------
# Hitting the player
# ---------------------------
# Starts tracking the blade's sweep for a new hit window
func _begin_hit() -> void:
	hit_done = false
	var points := blade_points()
	last_mid = points[1]
	last_tip = points[2]


# Checks where the blade went since the last frame against the player's body. Returns true when it lands.
func _check_blade_hit(damage_scale: float) -> bool:
	var points := blade_points()
	var guard: Vector3 = points[0]
	var mid: Vector3 = points[1]
	var tip: Vector3 = points[2]
	var swept := false
	if not hit_done and is_instance_valid(target):
		var low := target.global_position + Vector3.UP * PLAYER_LOW
		var high := target.global_position + Vector3.UP * PLAYER_HIGH
		# The blade now, and the paths of its tip and middle since the last frame (a fast swing jumps a long way)
		for segment in [[guard, tip], [last_tip, tip], [last_mid, mid]]:
			if _segment_distance(segment[0], segment[1], low, high) <= PLAYER_HIT_RADIUS:
				swept = true
				break
	last_mid = mid
	last_tip = tip
	if not swept:
		return false
	hit_done = true
	parryable = false   # it has connected: too late to parry
	if lunging and target.get("shield_blocking") == true:
		_shove_blocking_player(target)
	elif target.has_method("apply_push"):
		var away := target.global_position - global_position
		away.y = 0.0
		target.apply_push(away.normalized() * hit_knockback)
	_report_block(target)
	if target.has_method("damage"):
		target.damage(damage_to_player * damage_scale, true)
	if target.has_method("apply_camera_kick"):
		target.apply_camera_kick(0.04, randf_range(-0.03, 0.03))
	return true


# Shortest distance between segments p1-q1 and p2-q2
static func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return r.length()
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denominator := a * e - b * b
			s = clampf((b * f - c * e) / denominator, 0.0, 1.0) if denominator > 0.000001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


# ---------------------------
# The combo
# ---------------------------
func perform_attack() -> void:
	_perform_sword_combo()


func _perform_sword_combo() -> void:
	is_attacking = true
	var token := attack_token
	var parryable_strikes: Array = ["A", "C"] if parry_both_a_and_c else [["A", "C"].pick_random()]
	var last := ""
	for key in COMBO_ORDER:
		if last != "":
			# Backed off out of reach: he chases (a short sprint) and carries on rather than letting it drop. Only a
			# player who gets clean away (out of pursuit range, or outrunning the chase) ends the combo early.
			if not is_instance_valid(target) or _flat_distance_to_target() > combo_pursuit_range:
				break
			if _flat_distance_to_target() > combo_chain_range:
				if not await _pursue(token):
					return
				if _flat_distance_to_target() > combo_chain_range:
					break
		if not await _strike(STRIKES[key], key in parryable_strikes, token):
			return   # parried or cancelled: whoever cancelled it has moved it on
		last = key
		# The heavy finisher cut only air (dodged, not blocked): he overcommitted and is open for a moment
		if key == "C" and not hit_done:
			anim.play("Sword_Idle", 0.25)
			anim.speed_scale = 0.6
			if not await _hold_for(whiff_recovery, token):
				return
			anim.speed_scale = 1.0
	# Stopped before the end: the recovery out of the last strike
	var recovery: String = STRIKES[last]["recovery"] if last != "" else ""
	if recovery != "":
		anim.play(clip(recovery), 0.1)
		if not await _hold_for(SWORD_LIBRARY.get_animation(recovery).length, token):
			return
	velocity = Vector3.ZERO
	attack_timer.start(attack_cooldown)
	is_attacking = false
	release_attack_slot()


func _flat_distance_to_target() -> float:
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset.length()


# Between strikes: sprints after a player who stepped out of reach, until close enough to swing again or the chase
# runs out. Returns false if it was cancelled.
func _pursue(token: int) -> bool:
	anim.play("Sprint", 0.12)
	anim.speed_scale = 1.0
	var elapsed := 0.0
	while elapsed < combo_pursuit_time:
		await get_tree().physics_frame
		if token != attack_token or not is_inside_tree():
			return false
		if not is_instance_valid(target):
			break
		var step := get_physics_process_delta_time()
		elapsed += step
		face_target(step, 3.0)
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() <= combo_step_distance + 0.4:
			break
		velocity = to_target.normalized() * combo_pursuit_speed
		move_and_slide()
	velocity = Vector3.ZERO
	return true


# One swing: wind-up, the hit window, then on to its end. Returns false if it was cancelled.
# He tracks the player through the wind-up, then commits: the swing barely turns, so stepping or dashing out of its
# path as it starts makes it miss.
func _strike(strike: Dictionary, can_be_parried: bool, token: int) -> bool:
	anim.play(clip(strike["animation"]), 0.08)
	anim.speed_scale = 1.0
	audio_player.play("assets/audio/sfx/enemies/Enemy_Hit1.wav, assets/audio/sfx/enemies/Enemy_Hit2.wav, assets/audio/sfx/enemies/Enemy_Hit3.wav")
	var windup: float = strike["windup"]
	var hit_start: float = strike["hit"][0]
	var hit_end: float = strike["hit"][1]
	var parry_window_used := false
	if can_be_parried:
		glow_time = 0.0
		glow_strength = 0.0
		set_parry_glow(true)
		set_blade_glow(PARRY_COLOR, 2.5, windup)
	else:
		set_blade_glow(DANGER_COLOR, 3.0, 0.08)
	var hitting := false
	hit_done = false   # stays false through the swing if it never connects (read for the finisher's whiff)
	# Its own clock through the clip: right after play() the player can still report the previous clip's position
	var at := 0.0
	while true:
		await get_tree().physics_frame
		if token != attack_token or not is_inside_tree():
			_end_strike_fx()
			return false
		var step := get_physics_process_delta_time()
		at += step * anim.speed_scale
		var slow: bool = can_be_parried and strike.get("slow_when_parryable", false) and at < windup
		anim.speed_scale = parryable_windup_slowdown if slow else 1.0
		face_target(step, 1.5 if at < windup else 0.3)
		if at < windup:
			_combo_step_in()
		else:
			velocity = Vector3.ZERO
		if can_be_parried:
			# The parry window is short and sits right at the hit: it opens parry_lead real seconds before the swing
			# reaches the player (counting the slowed wind-up at its slowed pace) and shuts as the blade connects,
			# or parry_late after the hit window opens if it never does. The glow builds up to it.
			var to_hit := _real_time_to(hit_start, at, windup, slow)
			glow_strength = clampf(1.0 - (to_hit - parry_lead) / maxf(hit_start, 0.01), 0.0, 1.0)
			if not parry_window_used and to_hit <= parry_lead:
				parry_window_used = true
				_open_parry_window()
			if parryable and (hit_done or at >= hit_start + parry_late):
				parryable = false
		# The red strike leaves a red streak through its swing
		streak.active = not can_be_parried and at >= hit_start - STREAK_LEAD and at < hit_end + STREAK_TAIL
		if at >= hit_start and at < hit_end:
			if not hitting:
				hitting = true
				_begin_hit()
			_check_blade_hit(strike["damage"])
		elif at >= hit_end and (hitting or parryable):
			hitting = false
			_end_strike_fx()
		if at >= strike["end"]:
			break
	_end_strike_fx()
	anim.speed_scale = 1.0
	return true


# Real seconds from `at` (seconds into the clip) until `moment`, with the wind-up played at its slowed pace if `slow`
func _real_time_to(moment: float, at: float, windup: float, slow: bool) -> float:
	if at >= moment:
		return 0.0
	if slow and at < windup:
		return (minf(windup, moment) - at) / parryable_windup_slowdown + maxf(moment - windup, 0.0)
	return moment - at


func _end_strike_fx() -> void:
	streak.active = false
	parryable = false
	set_parry_glow(false)
	set_blade_glow(blade_material.emission, 0.0, 0.15)


# Waits while a recovery plays; false if cancelled
func _hold_for(seconds: float, token: int) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		if token != attack_token or not is_inside_tree():
			return false
		elapsed += get_physics_process_delta_time()
	return true


func on_parried() -> void:
	_end_strike_fx()
	anim.speed_scale = 1.0
	super()


func _on_shoved() -> void:
	_end_strike_fx()
	anim.speed_scale = 1.0
	super()


# ---------------------------
# States
# ---------------------------
class SwordIdleState extends EnemyStates.IdleState:
	func enter():
		super()
		enemy.anim.play("Sword_Idle")


# Parried: a flinch (the horde enemy's Hit_Chest) as it slides back, then on guard again while it's dazed
class SwordStunnedState extends EnemyHorde.StunnedState:
	func enter():
		super()
		enemy.anim.play("Hit_Chest", 0.05)
		enemy.anim.queue("Sword_Idle")


# The opening move from range: a red flash while it gathers itself, then Sword_Dash carries it at the player and
# slashes. The clip stays in place, so the body is moved here, fast enough to stop just short of the player.
class SwordDashState:
	var enemy
	var token := 0
	var at := 0.0   # its own clock through the clip, as in _strike()

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		enemy.lunging = true
		enemy.is_attacking = true
		enemy.last_tip = Vector3.INF   # the sweep starts fresh at the hit window
		token = enemy.attack_token
		at = 0.0
		enemy.anim.play(enemy.clip(DASH["animation"]), 0.15)
		enemy.anim.speed_scale = enemy.dash_windup_speed
		enemy.set_blade_glow(DANGER_COLOR, 3.0, 0.2)
		enemy.audio_player.play("assets/audio/sfx/enemies/Enemy_Hit1.wav, assets/audio/sfx/enemies/Enemy_Hit2.wav")

	func update(delta):
		if not is_instance_valid(enemy.target) or token != enemy.attack_token:
			enemy.resume_after_move()
			return
		at += delta * enemy.anim.speed_scale
		enemy.anim.speed_scale = enemy.dash_windup_speed if at < DASH["windup"] else 1.0
		enemy.face_target(delta, 4.0 if at < DASH["move"][1] else 0.5)
		if at >= DASH["move"][0] and at < DASH["move"][1]:
			var to_target: Vector3 = enemy.target.global_position - enemy.global_position
			to_target.y = 0.0
			var gap: float = maxf(to_target.length() - enemy.dash_strike_distance, 0.0)
			var time_left: float = maxf(DASH["move"][1] - at, 0.05)
			enemy.velocity = to_target.normalized() * minf(gap / time_left, enemy.lunge_speed)
			enemy.move_and_slide()
		else:
			enemy.velocity = Vector3.ZERO
		enemy.streak.active = at >= DASH["hit"][0] - STREAK_LEAD and at < DASH["hit"][1] + STREAK_TAIL
		if at >= DASH["hit"][0] and at < DASH["hit"][1]:
			if enemy.last_tip == Vector3.INF:
				enemy._begin_hit()
			enemy._check_blade_hit(enemy.dash_damage)
		elif at >= DASH["hit"][1]:
			enemy.set_blade_glow(DANGER_COLOR, 0.0, 0.2)
		if at >= DASH["end"]:
			enemy.is_attacking = false
			enemy.attack_timer.start(enemy.attack_cooldown * 0.5)
			enemy.resume_after_move()

	func exit():
		enemy.streak.active = false
		enemy.lunging = false
		enemy.is_attacking = false
		enemy.last_tip = Vector3.INF
		enemy.set_blade_glow(DANGER_COLOR, 0.0, 0.15)
		enemy.release_attack_slot()
		enemy.anim.speed_scale = 1.0
		enemy.velocity = Vector3.ZERO
		enemy._roll_lunge_cooldown()
