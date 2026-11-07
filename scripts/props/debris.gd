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

static var active := 0


static func spawn(tree: SceneTree, mesh: Mesh, material: Material, mesh_transform: Transform3D, at: Vector3, orientation: Basis, velocity: Vector3, spin: Vector3, collider_size := Vector3.ONE * 0.1) -> Debris:
	if active >= MAX_ACTIVE:
		return null
	var piece := Debris.new()
	piece.collision_layer = 0
	piece.collision_mask = PhysicsLayers.ENVIRONMENT
	piece.gravity_scale = GRAVITY_SCALE
	piece.linear_damp = 0.15
	piece.angular_damp = 0.4
	piece.can_sleep = true

	var shape := BoxShape3D.new()
	shape.size = collider_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	piece.add_child(collider)

	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.transform = mesh_transform
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_child(visual)

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


func _exit_tree() -> void:
	active -= 1
