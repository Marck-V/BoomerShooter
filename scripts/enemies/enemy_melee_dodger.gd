extends EnemyHorde
class_name EnemyMeleeDodger

# Melee enemy that weaves toward the target: while chasing it sidesteps at random, left or right and a little forward.
@export var dodge_interval_min: float = 1.0
@export var dodge_interval_max: float = 2.5
@export var dodge_speed: float = 11.0
@export var dodge_duration: float = 0.3
@export var dodge_range: float = 16.0   # only dodges this close to the target, where the player can see it

const DODGE_FORWARD := 0.5              # share of the sidestep that also closes the distance
const DODGE_BLOCKED_PADDING := 0.6
const FLOOR_CHECK_DEPTH := 1.0          # how far below its feet the floor can be at the end of a sidestep

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
	if destroyed or state != states["Chase"] or not is_instance_valid(target):
		return
	dodge_timer -= delta
	if dodge_timer <= 0.0 and global_position.distance_to(target.global_position) <= dodge_range:
		_try_dodge()


func _roll_dodge_timer() -> void:
	dodge_timer = randf_range(dodge_interval_min, dodge_interval_max)


func _try_dodge() -> void:
	if pick_dodge_direction() == Vector3.ZERO:
		dodge_timer = 0.3  # boxed in: try again shortly
		return
	change_state("Dodge")


# Random side, flipped if that way is blocked; ZERO if both are
func pick_dodge_direction() -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return Vector3.ZERO
	var forward := to_target.normalized()
	var side := forward.cross(Vector3.UP)
	if randf() < 0.5:
		side = -side
	for candidate in [(side + forward * DODGE_FORWARD).normalized(), (-side + forward * DODGE_FORWARD).normalized()]:
		if _can_dodge_toward(candidate):
			return candidate
	return Vector3.ZERO


# Enemies have no gravity, so a sidestep off an edge would leave it floating: it needs a clear way and floor to land on
func _can_dodge_toward(direction: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var reach := direction * (dodge_speed * dodge_duration + DODGE_BLOCKED_PADDING)
	var from := global_position + Vector3.UP * 0.9
	var wall_query := PhysicsRayQueryParameters3D.create(from, from + reach)
	wall_query.collision_mask = PhysicsLayers.SURFACE_MASK
	wall_query.exclude = [self]
	if not space.intersect_ray(wall_query).is_empty():
		return false
	var landing := from + reach
	var floor_query := PhysicsRayQueryParameters3D.create(landing, landing + Vector3.DOWN * (0.9 + FLOOR_CHECK_DEPTH))
	floor_query.collision_mask = PhysicsLayers.SURFACE_MASK
	floor_query.exclude = [self]
	return not space.intersect_ray(floor_query).is_empty()


func finish_dodge() -> void:
	_roll_dodge_timer()
	resume_after_move()
