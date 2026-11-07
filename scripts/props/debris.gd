extends RigidBody3D
class_name Debris

# A broken-off piece (a glass shard, a barrel stave) that tumbles to the floor, lies there a moment and shrinks away.
# Cheap on purpose: it only collides with the level (never the player or enemies), and the number alive at once is
# capped, so a big pane or a chain of barrels can't flood the physics.
#   Debris.spawn(tree, mesh, material, mesh_transform, world_position, orientation, velocity, spin)
# `mesh_transform` places the mesh relative to the piece's centre; that is where a shard's skew lives, since a body's
# own transform has to stay a plain rotation.

const MAX_ACTIVE := 110
const LIFETIME := 3.2
const SHRINK_TIME := 0.6
const GRAVITY_SCALE := 1.4
const SETTLE_CHECK := 0.08                  # seconds between checks for a piece that has stopped travelling
const SETTLE_DISTANCE := 0.012              # moved less than this (m) between checks = it has come to rest
const SETTLE_MIN_AGE := 0.3
const SETTLE_SLOW_SPEED := 0.7              # m/s sideways; below this and near the floor, it is done moving
const NEAR_FLOOR := 0.1                     # m above the floor that counts as having landed
const COLLIDER_PAD := 0.025                 # a fitted collider is this much thicker each side than the glass: the physics lets a piece sink about 1-2 cm into the floor, and this keeps the glass itself above it
const REST_GAP := 0.004                     # a settled piece lies this far above the floor

static var active := 0

var visual: MeshInstance3D
var _outline := PackedVector3Array()          # the mesh's corners, to find the glass's lowest point exactly
var _visual_base := Transform3D.IDENTITY
var _age := 0.0
var _since_check := 0.0
var _last_position := Vector3.ZERO
var _settled := false


static func spawn(tree: SceneTree, mesh: Mesh, material: Material, mesh_transform: Transform3D, at: Vector3, orientation: Basis, velocity: Vector3, spin: Vector3, collider_size := Vector3.ONE * 0.1, fit_collider := false) -> Debris:
	if active >= MAX_ACTIVE:
		return null
	var piece := Debris.new()
	piece.collision_layer = 0
	piece.collision_mask = PhysicsLayers.ENVIRONMENT
	piece.gravity_scale = GRAVITY_SCALE
	piece.linear_damp = 0.15
	piece.angular_damp = 1.5
	piece.can_sleep = true

	var collider := CollisionShape3D.new()
	if fit_collider:
		# The mesh's own outline, placed as the visual is: a box smaller than the piece lets its corners sink into the floor
		var hull := mesh.create_convex_shape(true, false)
		var fitted := PackedVector3Array()
		for point in hull.points:
			var placed := mesh_transform * point
			placed.z += signf(placed.z) * COLLIDER_PAD
			fitted.append(placed)
		hull.points = fitted
		collider.shape = hull
	else:
		var shape := BoxShape3D.new()
		shape.size = collider_size
		collider.shape = shape
	piece.add_child(collider)

	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.transform = mesh_transform
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_child(visual)
	piece.visual = visual
	piece._outline = mesh.get_faces()
	piece._visual_base = mesh_transform

	tree.current_scene.add_child(piece)
	piece.global_transform = Transform3D(orientation, at)
	piece.linear_velocity = velocity
	piece.angular_velocity = spin
	return piece


func _ready() -> void:
	active += 1
	var tween := create_tween()
	tween.tween_interval(LIFETIME * randf_range(0.8, 1.2))
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, SHRINK_TIME)
	tween.tween_callback(queue_free)


# A thin piece never quite stops on its own: it keeps rocking on the floor like a spun coin, sunk a little into it, so
# the glass flickers as it pokes through and back. Once it has stopped travelling, hold it still and set it on the floor.
func _physics_process(delta: float) -> void:
	if _settled:
		return
	_age += delta
	_since_check += delta
	if _since_check < SETTLE_CHECK:
		return
	_since_check = 0.0
	if _age < SETTLE_MIN_AGE:
		return
	# At rest: barely travelling since the last check, or slow and already down at the floor
	var slow := Vector2(linear_velocity.x, linear_velocity.z).length() < SETTLE_SLOW_SPEED
	if global_position.distance_to(_last_position) < SETTLE_DISTANCE or (slow and _height_above_floor() < NEAR_FLOOR):
		_settle()
	_last_position = global_position


# The glass's lowest point in the world (exact, from the mesh's corners)
func _lowest_y() -> float:
	var to_world := visual.global_transform
	var lowest := INF
	for point in _outline:
		lowest = minf(lowest, (to_world * point).y)
	return lowest


# How far the piece's lowest point is above the floor beneath it (INF when there is none)
func _height_above_floor() -> float:
	var floor_y = _floor_height()
	if floor_y == null or visual == null:
		return INF
	return _lowest_y() - floor_y


func _floor_height():
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 1.0, PhysicsLayers.ENVIRONMENT)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return null if hit.is_empty() else hit.position.y


# The physics lets a piece sink a little into the floor, and a fast one punches in for a frame on impact. The glass is
# only drawn, never collided, so each frame it is lifted back out: it can't be seen poking through.
func _process(_delta: float) -> void:
	if _settled or visual == null:
		return
	visual.transform = _visual_base
	var floor_y = _floor_height()
	if floor_y == null:
		return
	var below: float = floor_y + REST_GAP - _lowest_y()
	if below > 0.0:
		visual.global_position.y += below


func _settle() -> void:
	_settled = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if visual == null:
		return
	visual.transform = _visual_base
	var floor_y = _floor_height()
	if floor_y == null:
		return
	global_position.y += floor_y + REST_GAP - _lowest_y()


func _exit_tree() -> void:
	active -= 1
