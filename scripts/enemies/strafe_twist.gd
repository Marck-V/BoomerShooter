extends SkeletonModifier3D
class_name StrafeTwist

# Procedural strafing for the humanoid enemies, which only have forward walk and run clips.
#
# While an enemy moves one way and faces another (circling the player, or running along a path while it watches
# them), the hips and legs turn towards where it is actually going, so the walk steps that way, and the spine turns
# back by the same amount, so the chest and head keep facing where the body faces. Moving mostly backwards, the legs
# face the other way instead and the enemy plays its walk in reverse (see `backward`, read by EnemyHorde).
#
# The enemy feeds it `world_velocity` and `walking` every physics frame.

const MAX_TWIST := deg_to_rad(80.0)     # furthest the hips turn from the body
const BACKWARD_ENTER := deg_to_rad(115.0)  # moving further round than this from facing counts as backing away...
const BACKWARD_EXIT := deg_to_rad(95.0)    # ...until it comes back inside this (so it doesn't flicker at the edge)
const FULL_SPEED := 1.2                 # m/s at which the twist is at full strength
const TURN_RATE := 8.0                  # how quickly the twist follows a change of direction
const SPINE_BONES := ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]

var world_velocity := Vector3.ZERO
var walking := false                    # only while a walk or run clip is playing
var backward := false

var hips := -1
var spine: Array[int] = []
var twist := 0.0                        # radians the hips are turned, eased


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	hips = skeleton.find_bone("DEF-hips")
	for bone_name in SPINE_BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			spine.append(index)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hips < 0:
		return
	twist = lerp_angle(twist, _wanted_twist(skeleton), 1.0 - exp(-TURN_RATE * minf(delta, 0.1)))
	if absf(twist) < 0.002:
		return
	# Parents' poses as animated, before anything here moves them
	var bones: Array[int] = [hips]
	bones.append_array(spine)
	var parents: Array[Basis] = []
	for bone in bones:
		var parent := skeleton.get_bone_parent(bone)
		parents.append(skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY)
	# The hips turn by the twist; each spine bone turns a share of it back, so the chest ends up where it was
	for i in bones.size():
		var angle := twist if i == 0 else -twist / float(spine.size())
		var turn := Basis(Vector3.UP, angle)
		var local := Basis(skeleton.get_bone_pose_rotation(bones[i]))
		skeleton.set_bone_pose_rotation(bones[i], (parents[i].inverse() * turn * parents[i] * local).get_rotation_quaternion())


# How far round the hips should turn: towards the movement, in the skeleton's space (the body faces +Z)
func _wanted_twist(skeleton: Skeleton3D) -> float:
	var moving := skeleton.global_basis.inverse() * world_velocity
	moving.y = 0.0
	var speed := moving.length()
	if not walking or speed < 0.1:
		backward = false
		return 0.0
	var heading := atan2(moving.x, moving.z)   # 0 straight ahead, ±PI straight back
	if absf(heading) > BACKWARD_ENTER:
		backward = true
	elif absf(heading) < BACKWARD_EXIT:
		backward = false
	if backward:
		heading = wrapf(heading + PI, -PI, PI)   # the legs face away from the movement and walk it in reverse
	return clampf(heading, -MAX_TWIST, MAX_TWIST) * clampf(speed / FULL_SPEED, 0.0, 1.0)
