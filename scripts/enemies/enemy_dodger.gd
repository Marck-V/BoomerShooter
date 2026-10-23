extends EnemyRanged
class_name EnemyDodger

# Ranged enemy that periodically sidesteps at random, left or right of the line to the target.
@export var dodge_interval_min: float = 1.5
@export var dodge_interval_max: float = 3.5
@export var dodge_speed: float = 9.0
@export var dodge_duration: float = 0.35

const DODGE_BLOCKED_PADDING := 0.6  # extra clearance beyond the sidestep distance

var dodge_timer := 0.0


func _ready():
	super()
	_roll_dodge_timer()


func get_state_definitions() -> Dictionary:
	var definitions := super()
	definitions["Dodge"] = ENEMY_STATES.DodgeState.new(self)
	return definitions


func _physics_process(delta):
	super(delta)
	if destroyed or not is_instance_valid(target):
		return
	# Only dodge while engaged with the target
	if state != states["Chase"] and state != states["Attack"] and state != states["AttackIdle"]:
		return
	dodge_timer -= delta
	if dodge_timer <= 0.0:
		_try_dodge()


func _roll_dodge_timer() -> void:
	dodge_timer = randf_range(dodge_interval_min, dodge_interval_max)


func _try_dodge() -> void:
	if pick_dodge_direction() == Vector3.ZERO:
		# Boxed in on both sides: try again shortly
		dodge_timer = 0.3
		return
	change_state("Dodge")


# Random side, flipped if a wall is in the way; ZERO if both sides are blocked
func pick_dodge_direction() -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return Vector3.ZERO
	var side := to_target.normalized().cross(Vector3.UP)
	if randf() < 0.5:
		side = -side
	for candidate in [side, -side]:
		if not _is_blocked(candidate):
			return candidate
	return Vector3.ZERO


func _is_blocked(direction: Vector3) -> bool:
	var from := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * (dodge_speed * dodge_duration + DODGE_BLOCKED_PADDING))
	query.collision_mask = 1 | 2
	query.exclude = [self]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func finish_dodge() -> void:
	_roll_dodge_timer()
	change_state("Attack" if is_in_attack_range() else "Chase")
