extends SceneTree

# Copies sword animations from UAL2_Standard.glb onto the UAL1 rig (AnimationLibrary_Godot_Standard.glb, the
# "DEF-" skeleton every humanoid enemy uses) and saves them as an AnimationLibrary the sword enemy loads.
#
# Both files are the same Quaternius mannequin in the same rest pose; they only differ in bone names (UAL2 was
# imported with Godot's humanoid bone map) and bone axes. So each bone gets the same world-space rotation away from
# its rest as in the source, then that is turned into the target bone's own local rotation. The hips also get the
# source's movement. Run from the project folder:
#   godot --headless --path . -s tools/assetgen/retarget_ual2_sword.gd

const SOURCE := "res://models/enemies/UAL2_Standard.glb"
const TARGET := "res://models/enemies/AnimationLibrary_Godot_Standard.glb"
const OUTPUT := "res://models/enemies/sword_animations.res"
const FPS := 30.0

const ANIMATIONS := [
	"Sword_Regular_A", "Sword_Regular_A_Rec", "Sword_Regular_B", "Sword_Regular_B_Rec", "Sword_Regular_C",
	"Sword_Regular_Combo", "Sword_Dash", "Sword_Block", "Sword_Heavy_Combo", "Hit_Knockback",
]

# Humanoid profile name (the source's bones) -> the target's bone
const BONES := {
	"Root": "root", "Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002",
	"UpperChest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head",
	"LeftShoulder": "DEF-shoulder.L", "LeftUpperArm": "DEF-upper_arm.L", "LeftLowerArm": "DEF-forearm.L",
	"LeftHand": "DEF-hand.L", "RightShoulder": "DEF-shoulder.R", "RightUpperArm": "DEF-upper_arm.R",
	"RightLowerArm": "DEF-forearm.R", "RightHand": "DEF-hand.R",
	"LeftUpperLeg": "DEF-thigh.L", "LeftLowerLeg": "DEF-shin.L", "LeftFoot": "DEF-foot.L", "LeftToes": "DEF-toe.L",
	"RightUpperLeg": "DEF-thigh.R", "RightLowerLeg": "DEF-shin.R", "RightFoot": "DEF-foot.R", "RightToes": "DEF-toe.R",
}
const FINGERS := {"Thumb": "thumb", "Index": "f_index", "Middle": "f_middle", "Ring": "f_ring", "Little": "f_pinky"}
const MOVING_BONES := ["Root", "Hips"]   # the only bones whose position is copied; the rest keep the target's lengths

var src_sk: Skeleton3D
var dst_sk: Skeleton3D
var src_anim_player: AnimationPlayer
var bone_map := {}            # source bone index -> target bone index
var src_rest_global := []     # per source bone
var dst_rest_global := []     # per target bone


func _init() -> void:
	var src_root: Node = load(SOURCE).instantiate()
	var dst_root: Node = load(TARGET).instantiate()
	src_sk = src_root.find_children("*", "Skeleton3D", true, false)[0]
	dst_sk = dst_root.find_children("*", "Skeleton3D", true, false)[0]
	src_anim_player = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	var dst_path := String(dst_root.get_path_to(dst_sk))   # tracks are relative to the scene root

	var names := BONES.duplicate()
	for side in ["Left", "Right"]:
		var suffix := ".L" if side == "Left" else ".R"
		for finger in FINGERS:
			var parts := ["Metacarpal", "Proximal", "Distal"] if finger == "Thumb" else ["Proximal", "Intermediate", "Distal"]
			for i in 3:
				names["%s%s%s" % [side, finger, parts[i]]] = "DEF-%s.0%d%s" % [FINGERS[finger], i + 1, suffix]
	for src_name in names:
		var s := src_sk.find_bone(src_name)
		var d := dst_sk.find_bone(names[src_name])
		if s < 0 or d < 0:
			push_error("unmapped bone %s -> %s" % [src_name, names[src_name]])
			continue
		bone_map[s] = d

	for i in src_sk.get_bone_count():
		src_rest_global.append(src_sk.get_bone_global_rest(i))
	for i in dst_sk.get_bone_count():
		dst_rest_global.append(dst_sk.get_bone_global_rest(i))
	# Same mannequin, same rest pose: the joints should sit in the same places
	var worst := 0.0
	for s in bone_map:
		worst = maxf(worst, src_rest_global[s].origin.distance_to(dst_rest_global[bone_map[s]].origin))
	print("rest joints differ by at most %.4f m; source motion_scale %.3f, target %.3f" % [worst, src_sk.motion_scale, dst_sk.motion_scale])

	var library := AnimationLibrary.new()
	for anim_name in ANIMATIONS:
		if not src_anim_player.has_animation(anim_name):
			push_error("missing animation " + anim_name)
			continue
		var converted := _convert(src_anim_player.get_animation(anim_name), dst_path)
		library.add_animation(anim_name, converted)
		_report(anim_name, converted, dst_path)
	var err := ResourceSaver.save(library, OUTPUT)
	print("saved %s: %d animations (error %d)" % [OUTPUT, library.get_animation_list().size(), err])
	src_root.free()
	dst_root.free()
	quit(0 if err == OK else 1)


# Every source bone's pose at time t, in skeleton space. The source's tracks name the skeleton by its unique name
# (%GeneralSkeleton:Hips), so they are found by bone name.
func _source_globals(anim: Animation, t: float) -> Array:
	var tracks := {}
	for track in anim.get_track_count():
		tracks[[String(anim.track_get_path(track).get_subname(0)), anim.track_get_type(track)]] = track
	var globals := []
	globals.resize(src_sk.get_bone_count())
	for i in src_sk.get_bone_count():
		var rest := src_sk.get_bone_rest(i)
		var bone := src_sk.get_bone_name(i)
		var position := rest.origin
		var rotation := rest.basis.get_rotation_quaternion()
		var scale := rest.basis.get_scale()
		var track: int = tracks.get([bone, Animation.TYPE_POSITION_3D], -1)
		if track >= 0:
			position = anim.position_track_interpolate(track, t) * src_sk.motion_scale
		track = tracks.get([bone, Animation.TYPE_ROTATION_3D], -1)
		if track >= 0:
			rotation = anim.rotation_track_interpolate(track, t)
		track = tracks.get([bone, Animation.TYPE_SCALE_3D], -1)
		if track >= 0:
			scale = anim.scale_track_interpolate(track, t)
		var local := Transform3D(Basis(rotation).scaled(scale), position)
		var parent := src_sk.get_bone_parent(i)
		globals[i] = local if parent < 0 else globals[parent] * local
	return globals


# The target's local poses for the same moment: [rotation per bone, position per bone]
func _target_locals(source: Array) -> Array:
	var count := dst_sk.get_bone_count()
	var globals := []
	var rotations := []
	var positions := []
	globals.resize(count)
	rotations.resize(count)
	positions.resize(count)
	var from_target := {}
	for s in bone_map:
		from_target[bone_map[s]] = s
	for d in count:   # parents come before their children
		var rest := dst_sk.get_bone_rest(d)
		var parent := dst_sk.get_bone_parent(d)
		var parent_global: Transform3D = Transform3D() if parent < 0 else globals[parent]
		var world_rotation: Basis
		var origin: Vector3 = parent_global * rest.origin
		if from_target.has(d):
			var s: int = from_target[d]
			var delta: Basis = source[s].basis.orthonormalized() * src_rest_global[s].basis.orthonormalized().inverse()
			world_rotation = delta * dst_rest_global[d].basis.orthonormalized()
			if src_sk.get_bone_name(s) in MOVING_BONES:
				origin = source[s].origin - src_rest_global[s].origin + dst_rest_global[d].origin
		else:
			world_rotation = parent_global.basis.orthonormalized() * rest.basis.orthonormalized()
		globals[d] = Transform3D(world_rotation.scaled_local(rest.basis.get_scale()), origin)
		var local: Transform3D = parent_global.affine_inverse() * globals[d]
		rotations[d] = local.basis.get_rotation_quaternion()
		positions[d] = local.origin
	return [rotations, positions]


func _convert(anim: Animation, dst_path: String) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	out.step = 1.0 / FPS
	var rotation_tracks := {}
	var position_tracks := {}
	for s in bone_map:
		var d: int = bone_map[s]
		var path := NodePath("%s:%s" % [dst_path, dst_sk.get_bone_name(d)])
		if src_sk.get_bone_name(s) in MOVING_BONES:
			position_tracks[d] = out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(position_tracks[d], path)
		rotation_tracks[d] = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rotation_tracks[d], path)
	var frames := int(ceil(anim.length * FPS))
	for f in frames + 1:
		var t := minf(f / FPS, anim.length)
		var pose := _target_locals(_source_globals(anim, t))
		for d in rotation_tracks:
			out.rotation_track_insert_key(rotation_tracks[d], t, pose[0][d])
		for d in position_tracks:
			out.position_track_insert_key(position_tracks[d], t, pose[1][d] / dst_sk.motion_scale)
	return out


# What placing the sword and timing its hits needs: the grip in the right hand's own space, and when the blade tip
# whips round fastest and how far in front of the body it is then (the model faces +Z)
func _report(anim_name: String, anim: Animation, _dst_path: String) -> void:
	var hand := dst_sk.find_bone("DEF-hand.R")
	var line := ""
	var previous := Vector3.INF
	var frames := int(ceil(anim.length * FPS))
	for f in frames + 1:
		var t := minf(f / FPS, anim.length)
		var globals := _target_globals(anim, t)
		var tip: Vector3 = globals[hand] * (GRIP + BLADE_AXIS * 0.9)
		if previous != Vector3.INF:
			line += " %.2f:%.0f/%.1f" % [t, (tip - previous).length() * FPS, tip.z]
		previous = tip
		if anim_name == "Sword_Regular_A" and f == 6:
			print("  grip (hand.R space) %s  blade axis %s" % [_grip_local(globals), _blade_axis_local(globals)])
	print("%s %.2fs  t:tip speed/reach ->%s" % [anim_name, anim.length, line])


# Placeholder grip for the report, refined from what _grip_local prints
const GRIP := Vector3(0.0, 0.1, 0.03)
const BLADE_AXIS := Vector3(0.0, 0.17, 0.98)


# The target's bone poses in skeleton space at time t, from a converted animation
func _target_globals(anim: Animation, t: float) -> Array:
	var globals := []
	globals.resize(dst_sk.get_bone_count())
	for d in dst_sk.get_bone_count():
		var rest := dst_sk.get_bone_rest(d)
		var position := rest.origin
		var rotation := rest.basis.get_rotation_quaternion()
		var path := NodePath("Rig/Skeleton3D:%s" % dst_sk.get_bone_name(d))
		var track := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if track >= 0:
			rotation = anim.rotation_track_interpolate(track, t)
		track = anim.find_track(path, Animation.TYPE_POSITION_3D)
		if track >= 0:
			position = anim.position_track_interpolate(track, t)
		var local := Transform3D(Basis(rotation).scaled(rest.basis.get_scale()), position)
		var parent := dst_sk.get_bone_parent(d)
		globals[d] = local if parent < 0 else globals[parent] * local
	return globals


# Middle of the curled fingers, in the right hand bone's space
func _grip_local(globals: Array) -> Vector3:
	var hand_inverse: Transform3D = globals[dst_sk.find_bone("DEF-hand.R")].affine_inverse()
	var sum := Vector3.ZERO
	for finger in ["f_index", "f_middle", "f_ring", "f_pinky"]:
		sum += hand_inverse * globals[dst_sk.find_bone("DEF-%s.02.R" % finger)].origin
	return sum / 4.0


# Along the fist, from the little finger to the index: the way the blade points out of it
func _blade_axis_local(globals: Array) -> Vector3:
	var hand_inverse: Transform3D = globals[dst_sk.find_bone("DEF-hand.R")].affine_inverse()
	var index: Vector3 = hand_inverse * globals[dst_sk.find_bone("DEF-f_index.01.R")].origin
	var pinky: Vector3 = hand_inverse * globals[dst_sk.find_bone("DEF-f_pinky.01.R")].origin
	return (index - pinky).normalized()
