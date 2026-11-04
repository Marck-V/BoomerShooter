extends SkeletonModifier3D
class_name HitRecoil

# Procedural hit reactions for the humanoid enemies, layered over whatever animation is playing.
#
# The spine, neck, head and arms each hang on a damped spring: a hit gives them a spin away from the shot, and they
# overshoot and wobble back to the animated pose, the head and arms faster than the spine. Bones near the hit react
# most (a headshot snaps the head, a hit on one side twists the torso). A parry is a big kick that arches the upper
# body back and flings the weapon arm up, followed by a dazed sway that fades out over the stun. The hips and legs are
# left alone so the feet stay planted.
#
# Spring offsets are rotations in the skeleton's space, applied on top of the animated pose each frame.

const DAMPING := 0.38            # share of critical damping: low enough to overshoot and settle with a wobble
const MAX_ANGLE := 0.9           # radians any one bone can be thrown
const MAX_SPIN := 25.0           # radians per second
const HIT_SPIN := 3.2            # a gunshot's kick, at strength 1
const PARRY_SPIN := 11.0         # a parry's kick
const TWIST_SHARE := 0.6         # how much of a hit off to one side turns into twist
const DAZE_SWAY := 0.07          # radians of sway at the start of a stun

# bone: [share of a kick it takes, spring stiffness, share of a parry's kick]
const BONES := {
	"DEF-spine.001": [0.25, 90.0, 0.3],
	"DEF-spine.002": [0.3, 110.0, 0.35],
	"DEF-spine.003": [0.35, 130.0, 0.4],
	"DEF-neck": [0.3, 160.0, 0.35],
	"DEF-head": [0.5, 200.0, 0.55],
	"DEF-upper_arm.R": [0.35, 70.0, 1.1],
	"DEF-forearm.R": [0.25, 90.0, 0.6],
	"DEF-upper_arm.L": [0.3, 80.0, 0.6],
	"DEF-forearm.L": [0.2, 100.0, 0.35],
}

var bones: Array[int] = []       # parents before children
var weights: Array[float] = []
var parry_weights: Array[float] = []
var stiffness: Array[float] = []
var angles: Array[Vector3] = []
var spins: Array[Vector3] = []
var daze_left := 0.0
var daze_total := 0.0
var daze_time := 0.0
var ignore_until_msec := 0       # a parry's own hit flash comes straight after it: don't kick twice


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var found := []
	for bone_name in BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			found.append([index, BONES[bone_name]])
	found.sort_custom(func(a, b): return a[0] < b[0])   # bone indices already list parents first
	for entry in found:
		bones.append(entry[0])
		weights.append(entry[1][0])
		stiffness.append(entry[1][1])
		parry_weights.append(entry[1][2])
		angles.append(Vector3.ZERO)
		spins.append(Vector3.ZERO)


# A shot landing at world_point, travelling along `direction`. Strength 1 is an ordinary bullet.
func hit(world_point: Vector3, direction: Vector3, strength := 1.0) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bones.is_empty() or Time.get_ticks_msec() < ignore_until_msec:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var away := _flat(skeleton.global_basis.inverse() * direction)
	if away == Vector3.ZERO:
		return
	var point := to_skeleton * world_point
	var tip := Vector3.UP.cross(away)   # spinning about this throws the top of a bone along `away`
	var side := Vector3.UP.cross(away).normalized()
	var off_centre := clampf(point.dot(side) / 0.25, -1.0, 1.0)   # how far the hit is to one side of the spine
	for i in bones.size():
		var bone_point := skeleton.get_bone_global_pose(bones[i]).origin
		var near := clampf(1.3 - absf(bone_point.y - point.y) * 1.4, 0.3, 1.3)
		var kick := tip * near + Vector3.UP * off_centre * TWIST_SHARE
		spins[i] += kick * HIT_SPIN * strength * weights[i]


# Caught by a parry: the upper body is thrown back from `direction` (from the player to the enemy) and the arms
# flung up, then it sways, dazed, for `daze_seconds`
func parry(direction: Vector3, daze_seconds: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bones.is_empty():
		return
	var away := _flat(skeleton.global_basis.inverse() * direction)
	if away == Vector3.ZERO:
		return
	var tip := Vector3.UP.cross(away)
	var twist := Vector3.UP * randf_range(-0.35, 0.35)
	for i in bones.size():
		spins[i] += (tip + twist) * PARRY_SPIN * parry_weights[i]
	daze_left = daze_seconds
	daze_total = maxf(daze_seconds, 0.01)
	daze_time = randf() * 10.0
	ignore_until_msec = Time.get_ticks_msec() + 150


func calm() -> void:
	daze_left = 0.0
	for i in bones.size():
		angles[i] = Vector3.ZERO
		spins[i] = Vector3.ZERO


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else Vector3.ZERO


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bones.is_empty():
		return
	_step(delta)
	var sway := _daze_sway(delta)

	# Every parent's pose as animated, before anything here moves it
	var parents: Array[Basis] = []
	for bone in bones:
		var parent := skeleton.get_bone_parent(bone)
		parents.append(skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY)
	for i in bones.size():
		var offset: Vector3 = angles[i] + sway[i]
		var angle := offset.length()
		if angle < 0.0001:
			continue
		# A rotation R in the skeleton's space becomes P^-1 R P in the bone's own: the parent's rotation (applied
		# first, being earlier in the list) then carries this bone round with it
		var spin := Basis(offset / angle, angle)
		var local := Basis(skeleton.get_bone_pose_rotation(bones[i]))
		var turned: Basis = parents[i].inverse() * spin * parents[i] * local
		skeleton.set_bone_pose_rotation(bones[i], turned.get_rotation_quaternion())


func _step(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	for i in bones.size():
		var k := stiffness[i]
		var c := 2.0 * DAMPING * sqrt(k)
		spins[i] += (-angles[i] * k - spins[i] * c) * delta
		spins[i] = spins[i].limit_length(MAX_SPIN)
		angles[i] = (angles[i] + spins[i] * delta).limit_length(MAX_ANGLE)


# A slow, fading sway of the spine and head while dazed
func _daze_sway(delta: float) -> Array:
	var sway := []
	sway.resize(bones.size())
	sway.fill(Vector3.ZERO)
	if daze_left <= 0.0:
		return sway
	daze_left -= delta
	daze_time += delta
	var fade := clampf(daze_left / daze_total, 0.0, 1.0)
	var amount := DAZE_SWAY * fade * fade
	var wobble := Vector3(sin(daze_time * 1.6) * 0.7, 0.0, sin(daze_time * 2.3)) * amount
	for i in bones.size():
		sway[i] = wobble * (weights[i] / 0.3)
	return sway
