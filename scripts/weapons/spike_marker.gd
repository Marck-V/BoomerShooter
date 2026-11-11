extends Node3D

# Purely visual: the spikes the rifle's Conductor Rounds have planted in an enemy. Each one is stuck in where the shot
# landed, leaning back toward the shooter, and rides the nearest bone of the enemy's skeleton so it moves with the
# animation (an enemy without a skeleton carries it on its body). Child of the enemy; goes when the spikes are set off or
# fade.
# Use: SpikeMarker.plant(enemy, world_point)

const LENGTH := 0.2
const RADIUS := 0.022
const SUNK := 0.07                     # how much of the spike is buried in the body
const LEAN := deg_to_rad(18.0)         # random tilt away from pointing straight at the shooter
const SKIN_COLOR := Color(0.035, 0.04, 0.05)
const GLOW_COLOR := Color(0.1, 0.45, 0.6)
const GLOW_ENERGY := 0.15
const SPIKE_MAX := 5                   # EnemyBase.SPIKE_MAX

var enemy: Node3D
var skeleton: Skeleton3D
var material: StandardMaterial3D
var mesh: CylinderMesh
var spikes: Array[Dictionary] = []     # {node, bone (-1 = on the body), local}


static func plant(target: Node3D, world_point: Vector3) -> void:
	if not is_instance_valid(target):
		return
	var marker := target.get_node_or_null("SpikeMarker")
	if marker == null:
		marker = new()
		marker.name = "SpikeMarker"
		marker.enemy = target
		target.add_child(marker)
	marker.add_spike(world_point)


func _ready() -> void:
	skeleton = enemy.find_child("Skeleton3D", true, false) as Skeleton3D
	material = StandardMaterial3D.new()
	material.albedo_color = SKIN_COLOR
	material.metallic = 0.3
	material.roughness = 0.6
	material.emission_enabled = true
	material.emission = GLOW_COLOR
	material.emission_energy_multiplier = GLOW_ENERGY
	mesh = CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = RADIUS
	mesh.height = LENGTH
	mesh.radial_segments = 5
	mesh.rings = 1


func add_spike(world_point: Vector3) -> void:
	if spikes.size() >= SPIKE_MAX:
		spikes.pop_front().node.queue_free()

	if world_point == Vector3.INF:
		# No impact point: somewhere on the torso, facing outward
		var angle := randf() * TAU
		world_point = enemy.global_position + Vector3(cos(angle) * 0.25, randf_range(0.9, 1.5), sin(angle) * 0.25)

	# It leans back toward the shooter, a little off-axis so a stack doesn't look combed
	var camera := get_viewport().get_camera_3d()
	var direction := (camera.global_position - world_point).normalized() if camera else Vector3.UP
	var side := direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized()
	direction = direction.rotated(side, randf_range(-LEAN, LEAN))
	direction = direction.rotated(direction.cross(side).normalized(), randf_range(-LEAN, LEAN)).normalized()

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

	# The cone's tip is +Y; its middle sits so that SUNK of it is inside the body
	var world := Transform3D(Basis(Quaternion(Vector3.UP, direction)), world_point + direction * (LENGTH * 0.5 - SUNK))
	var bone := _nearest_bone(world_point)
	var reference := _reference(bone)
	spikes.append({"node": instance, "bone": bone, "local": reference.affine_inverse() * world})
	instance.global_transform = world


# The transform a spike's local one is relative to: its bone, or the enemy's body
func _reference(bone: int) -> Transform3D:
	if bone >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	return enemy.global_transform


# The bone whose stretch (from its joint to its first child's) is closest to the point, -1 without a skeleton
func _nearest_bone(world_point: Vector3) -> int:
	if skeleton == null or skeleton.get_bone_count() == 0:
		return -1
	var point := skeleton.global_transform.affine_inverse() * world_point
	var best := -1
	var best_d2 := INF
	for bone in skeleton.get_bone_count():
		var start := skeleton.get_bone_global_pose(bone).origin
		var children := skeleton.get_bone_children(bone)
		var end := skeleton.get_bone_global_pose(children[0]).origin if children.size() > 0 else start
		var closest := Geometry3D.get_closest_point_to_segment(point, start, end)
		var d2 := point.distance_squared_to(closest)
		if d2 < best_d2:
			best_d2 = d2
			best = bone
	return best


func _process(_delta: float) -> void:
	if not is_instance_valid(enemy) or enemy.spikes <= 0 or Time.get_ticks_msec() >= enemy.spikes_expire_msec:
		queue_free()
		return
	for spike in spikes:
		spike.node.global_transform = _reference(spike.bone) * spike.local
