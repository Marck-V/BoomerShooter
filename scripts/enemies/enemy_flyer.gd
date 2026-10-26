extends EnemyBase
class_name EnemyFlyer

# Flying enemy: hovers above the ground at a set distance from the target, shoots energy balls and
# periodically sidesteps in the air (left/right with a little vertical drift).
const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@export var shoot_range: float = 20.0
@export var firing_rate: float = 2.0
@export var energy_ball_scene: PackedScene = preload("res://scenes/enemies/energy_ball.tscn")

# --- Hovering ---
@export var preferred_distance: float = 12.0   # horizontal distance it tries to hold from the target
@export var hover_height: float = 4.0          # height above the target's position
@export var bob_height: float = 0.4
@export var bob_speed: float = 2.0
@export var acceleration: float = 5.0

# --- Dodging ---
@export var dodge_interval_min: float = 1.5
@export var dodge_interval_max: float = 3.5
@export var dodge_speed: float = 10.0
@export var dodge_duration: float = 0.35
@export var dodge_vertical_drift: float = 0.4   # max up/down share of the sidestep

const DODGE_BLOCKED_PADDING := 0.6
const VISUAL_SCALE := 1.6  # the Kenney model is ~0.6 m; matches the Visual node scale in the scene

@onready var shoot_timer: Timer = $ShootTimer
@onready var spawn_marker: Marker3D = $EnergyBallSpawnMarker
@onready var vision_area: Area3D = $VisionArea

var dodge_timer := 0.0
var bob_time := 0.0


func _ready():
	_build_animations()  # before super(): the Idle state plays "Idle" as soon as the base class is ready
	super()
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	shoot_timer.wait_time = firing_rate
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))
	bob_time = randf() * TAU
	_roll_dodge_timer()

	attack_animation_action = "Spell_Simple_Shoot"


# The Kenney flyer model has no skeleton or baked animations: the mesh we flash and tint is its torso
func _find_model() -> MeshInstance3D:
	return find_child("torso", true, false) as MeshInstance3D


# Procedural animations on the "Visual" node (never on Enemy_Model, which the flinch jolts)
func _build_animations() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("Idle", _make_idle_animation())
	library.add_animation("Spell_Simple_Shoot", _make_shoot_animation())
	anim.add_animation_library("", library)


func _make_idle_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 1.6
	animation.loop_mode = Animation.LOOP_LINEAR
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, "Visual:rotation")
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 0.4, Vector3(0.0, 0.0, 0.09))
	animation.track_insert_key(track, 0.8, Vector3.ZERO)
	animation.track_insert_key(track, 1.2, Vector3(0.0, 0.0, -0.09))
	return animation


# Quick recoil: the model kicks back and squashes as the blasters fire
func _make_shoot_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.35
	var kick := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(kick, "Visual:position")
	animation.track_insert_key(kick, 0.0, Vector3.ZERO)
	animation.track_insert_key(kick, 0.08, Vector3(0.0, 0.0, -0.18))
	animation.track_insert_key(kick, 0.35, Vector3.ZERO)
	var squash := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(squash, "Visual:scale")
	animation.track_insert_key(squash, 0.0, Vector3.ONE * VISUAL_SCALE)
	animation.track_insert_key(squash, 0.08, Vector3(1.15, 1.15, 0.85) * VISUAL_SCALE)
	animation.track_insert_key(squash, 0.35, Vector3.ONE * VISUAL_SCALE)
	return animation


func get_state_definitions() -> Dictionary:
	return {
		"Idle": ENEMY_STATES.IdleState.new(self),
		"Fly": FlyState.new(self),
		"Dodge": FlyDodgeState.new(self),
		"Dead": ENEMY_STATES.DeadState.new(self),
	}


func _on_body_entered(body: Node3D):
	if body == target:
		change_state("Fly")


func _on_body_exited(body: Node3D):
	if body == target:
		change_state("Idle")


func _physics_process(delta):
	super(delta)
	if destroyed or not is_instance_valid(target) or state != states["Fly"]:
		return
	dodge_timer -= delta
	if dodge_timer <= 0.0:
		_try_dodge()


# ---------------------------
# Shooting
# ---------------------------
func is_in_attack_range() -> bool:
	if not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > shoot_range:
		return false
	return has_line_of_sight_to_player()


func can_attack() -> bool:
	return shoot_timer.is_stopped()


func has_line_of_sight_to_player() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
			spawn_marker.global_position, target.global_position + Vector3.UP)
	query.exclude = [self]
	query.collision_mask = 2  # Environment layer
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func perform_attack():
	anim.play(attack_animation_action)
	anim.queue(attack_idle_animation)

	var ball := energy_ball_scene.instantiate() as Area3D
	ball.shooter = self
	get_parent().add_child(ball)
	# The ball flies along its +Z axis, so aim -Z away from the target
	var aim: Vector3 = (target.global_position + Vector3.UP - spawn_marker.global_position).normalized()
	ball.global_transform = Transform3D(Basis.looking_at(-aim, Vector3.UP), spawn_marker.global_position)
	if ball.has_method("set_target"):
		ball.set_target(target)

	audio_player.play_at(global_position,
		"assets/audio/sfx/enemies/Enemy_Shoot1_PitchedUp.wav, \
		 assets/audio/sfx/enemies/Enemy_Shoot2_PitchedUp.wav")
	shoot_timer.start()


# ---------------------------
# Flight
# ---------------------------
func face_target(delta: float) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return
	var target_basis := Basis.looking_at(to_target.normalized(), Vector3.UP).rotated(Vector3.UP, deg_to_rad(180))
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * rotation_speed * 2.0)


# Drifts toward the hover point: preferred_distance away from the target, hover_height above it
func hover(delta: float) -> void:
	bob_time += delta * bob_speed
	var away := global_position - target.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.001 else -global_basis.z
	# Without a clear shot (behind a wall), close in instead of holding distance
	var distance := preferred_distance if has_line_of_sight_to_player() else preferred_distance * 0.25
	var goal := target.global_position + away * distance \
			+ Vector3.UP * (hover_height + sin(bob_time) * bob_height)

	var to_goal := goal - global_position
	var speed_scale := clampf(to_goal.length() / 2.0, 0.0, 1.0)
	var desired := to_goal.normalized() * movement_speed * speed_scale
	velocity = velocity.lerp(desired, 1.0 - exp(-acceleration * delta))
	move_and_slide()


# ---------------------------
# Dodge
# ---------------------------
func _roll_dodge_timer() -> void:
	dodge_timer = randf_range(dodge_interval_min, dodge_interval_max)


func _try_dodge() -> void:
	if pick_dodge_direction() == Vector3.ZERO:
		dodge_timer = 0.3  # boxed in: try again shortly
		return
	change_state("Dodge")


# Random side (with a bit of vertical drift), flipped if a wall is in the way; ZERO if both are blocked
func pick_dodge_direction() -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return Vector3.ZERO
	var side := to_target.normalized().cross(Vector3.UP)
	if randf() < 0.5:
		side = -side
	var lift := Vector3.UP * randf_range(-dodge_vertical_drift, dodge_vertical_drift)
	for candidate in [(side + lift).normalized(), (-side + lift).normalized()]:
		if not _is_blocked(candidate):
			return candidate
	return Vector3.ZERO


func _is_blocked(direction: Vector3) -> bool:
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * (dodge_speed * dodge_duration + DODGE_BLOCKED_PADDING))
	query.collision_mask = 1 | 2
	query.exclude = [self]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func finish_dodge() -> void:
	_roll_dodge_timer()
	change_state("Fly")


# ---------------------------
# States
# ---------------------------
class FlyState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.anim.play("Idle")
		enemy.should_move = false

	func update(delta):
		if not is_instance_valid(enemy.target):
			enemy.change_state("Idle")
			return
		enemy.face_target(delta)
		enemy.hover(delta)
		if enemy.can_attack() and enemy.is_in_attack_range():
			enemy.perform_attack()


class FlyDodgeState:
	var enemy
	var dodge_velocity := Vector3.ZERO
	var time_left := 0.0

	func _init(e):
		enemy = e

	func enter():
		time_left = enemy.dodge_duration
		dodge_velocity = enemy.pick_dodge_direction() * enemy.dodge_speed
		DodgeSmear.vanish(enemy, dodge_velocity)

	func update(delta):
		time_left -= delta
		if is_instance_valid(enemy.target):
			enemy.face_target(delta)
		# Ease out over the last part of the step so it doesn't stop dead
		var ease_factor := clampf(time_left / maxf(enemy.dodge_duration * 0.4, 0.001), 0.0, 1.0)
		enemy.velocity = dodge_velocity * ease_factor
		enemy.move_and_slide()
		if time_left <= 0.0:
			enemy.finish_dodge()

	func exit():
		enemy.is_dodging = false
		enemy.set_dodge_vanished(false)
