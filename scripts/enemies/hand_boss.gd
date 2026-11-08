extends EnemyBase
class_name HandBoss

# The giant hand at the end of level 02. It reaches down through a portal in the sky over a round arena with a
# water floor. The model and its clips come from tools/assetgen/hand_boss.py: the clips only move the fingers and
# the wrist, and this script moves the whole hand through the arena.
#
# The fight has three phases, changing at set fractions of its health:
#   1 The Touch    fist slam, three pokes (parry the third and its finger sticks in the floor), flick (parry the
#                  orb back into it to stagger it)
#   2 Puppeteer    adds the palm sweep and the mortar barrage
#   3 Fury         adds the spoke burst and the crush, and the palm sweep comes back the way it went; faster, with
#                  shorter gaps
# On each change it clenches, shakes and bursts open, throwing the player back, and can't be hurt for a moment.
# Weak points, where hits count as critical: the knuckles while the fist or the flat hand is planted after a slam
# or a crush, and the palm while it is open (mortar barrage, stuck finger, stagger).
#
# The map's hand_boss entity puts it on the arena floor in wave "boss": the wave trigger holds it out of the level
# until the player walks in, then it punches down through the portal as a fist and slams into the water.
#
# How it moves: the root is the wrist. Every attack is a coroutine of glide()/wait()/track() steps, and each of
# those returns false as soon as action_token changes. interrupt() bumps the token and queues a reaction (stagger,
# stuck finger, phase change), so whatever the hand was doing stops cleanly and _brain() runs the reaction next.

const ENERGY_BALL: PackedScene = preload("res://scenes/enemies/energy_ball.tscn")
const HAND_SHADER: Shader = preload("res://shaders/boss/hand_boss.gdshader")
const PORTAL_SHADER: Shader = preload("res://shaders/boss/dark_portal.gdshader")
const HURTBOX_SCRIPT: Script = preload("res://scripts/enemies/body_hurtbox.gd")
const BLOOD_PARTICLES = preload("res://scripts/weapons/blood_particles.gd")
const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")

const PHASES := [
	{"name": "The Touch", "speed": 1.0, "gap": 1.4, "attacks": ["slam", "poke", "flick"]},
	{"name": "Puppeteer", "speed": 1.12, "gap": 1.1, "attacks": ["slam", "poke", "flick", "sweep", "mortar"]},
	{"name": "Fury", "speed": 1.3, "gap": 0.7, "attacks": ["slam", "poke", "flick", "sweep", "mortar", "spokes", "crush"]},
]
const COOLDOWNS := {"slam": 7.0, "poke": 8.0, "flick": 9.0, "sweep": 12.0, "mortar": 11.0,
		"spokes": 12.0, "crush": 20.0}

const SFX_ROAR := "assets/audio/sfx/boss/Boss_Roar1.wav, assets/audio/sfx/boss/Boss_Roar2.wav"
const SFX_HIT := "assets/audio/sfx/boss/Boss_Hit1.wav, assets/audio/sfx/boss/Boss_Hit2.wav, assets/audio/sfx/boss/Boss_Hit3.wav"
const SFX_DEATH := "assets/audio/sfx/boss/Boss_Death1.wav"
const SFX_SHOOT := "assets/audio/sfx/enemies/Enemy_Shoot1_PitchedUp.wav, assets/audio/sfx/enemies/Enemy_Shoot2_PitchedUp.wav"

# Yellow is kept for "you can parry this" (the last poke, the flick), red for "this can't be parried:
# get out of the way", so the colour alone tells the player whether to raise the shield or move
const PARRY_GLOW := Color(1.0, 0.8, 0.15)       # yellow: parryable
const DANGER_GLOW := Color(1.0, 0.1, 0.04)       # red: not parryable
const WEAK_GLOW := Color(0.55, 0.85, 1.0)        # pale blue: open to critical hits
const WARN_COLOR := Color(1.0, 0.25, 0.1)

const FINGERS := ["index", "middle", "ring", "pinky"]

enum Ease { SMOOTH, IN, OUT, LINEAR }

@export_category("Basic Attributes")
@export var boss_name := "The Hand"         # shown under the health bar
@export var hand_scale := 2.5               # the model's scale: about 13.5 m from wrist to fingertip at 2.5
@export var arena_radius := 26.0            # the arena it keeps to, around where it is placed
@export var wake_distance := 45.0           # starts its entrance once the player is this close
@export var hover_clearance := 5.0          # meters between its fingertips and the floor while it hovers

@export_category("Entrance")
@export var portal_height := 36.0           # meters above the floor that the portal opens
@export var entrance_windup := 0.35        # the portal tears open with the fist still out of sight
@export var entrance_time := 0.5            # the punch from the portal down to the water

@export_category("Fist Slam")
@export var slam_track_time := 1.3
@export var slam_damage := 45.0
@export var slam_hold := 1.2                # planted, knuckles exposed

@export_category("Poke")
@export var poke_damage := 30.0
@export var poke_radius := 2.6
@export var poke_warn := 0.75
@export var stuck_time := 3.5

@export_category("Flick")
@export var flick_damage := 35.0
@export var flick_charge := 1.3
@export var flick_orb_speed := 20.0         # m/s on the way to the player (a parried one comes back 4x faster)
@export var flick_reflect_fraction := 0.06  # share of its full health a parried orb takes off
@export var stagger_time := 2.8

@export_category("Palm Sweep")
@export var sweep_damage := 40.0
@export var sweep_time := 1.5
@export var sweep_clearance := 2.2          # feet higher than this above the floor clear the sweep

@export_category("Mortar Barrage")
@export var mortar_waves := 3               # one more in the last phase
@export var mortar_damage := 30.0           # at the centre of a shell's splash; half at its edge
@export var mortar_radius := 3.6
@export var mortar_rise := 0.5              # seconds from the fingertip up out of sight
@export var mortar_fall := 1.4              # seconds from the sky down to the floor: the time the player has to move
@export var mortar_scatter := 9.0           # how far round the player the other shells of a wave land

@export_category("Spoke Burst")
@export var spoke_damage := 14.0            # per tick while standing in a burning spoke (jumping clears a tick)
@export var spoke_beats := 5                # sets of spokes in a row
@export var spoke_warn := 1.0               # a set of spokes fills this long before it ignites
@export var spoke_beat := 1.4               # seconds from one set's ignition to the next
@export var spoke_burn := 1.0               # how long a set burns
@export var spoke_half_angle := 18.0        # degrees: each spoke is twice this wide, with a quarter turn between them
@export var spoke_surge_speed := 60.0       # m/s the fire surges out along a spoke
@export var spoke_height := 9.0             # metres above the water the wrist hangs

@export_category("Crush")
@export var crush_damage := 65.0
@export var crush_track_time := 1.5
@export var crush_hold := 2.2

@export_category("Phases")
@export var phase_two_at := 0.66
@export var phase_three_at := 0.33
@export var crit_multiplier := 2.5          # hits on an exposed weak point
@export var open_multiplier := 1.5          # any hit while it is staggered or stuck

# --- Fight state ---
var phase := 1
var max_health := 0.0
var invulnerable := true
var vulnerability := 1.0
var parryable := false                      # read by the player's shield (see parry_point())
var knuckles_exposed := false
var palm_open := false
var action_token := 0
var pending_reaction := ""
var cooldown_until := {}
var awake := false
var frames_in_level := 0                    # frames (process, not physics) since it last entered the tree
var home := Vector3.ZERO                    # the arena floor under where it was placed
var floor_y := 0.0
var hand_length := 13.5                     # wrist to middle fingertip, meters
var forearm_length := 9.75
var palm_half_width := 2.8
var hurtboxes := {}                         # bone name -> its hurtbox Area3D
var action_fx: Array = []                   # telegraphs made by the current action, cleared when it ends
var health_bar: Control

# --- Look ---
var skeleton: Skeleton3D
var skin: ShaderMaterial
var glow_tween: Tween
var portal: Node3D
var portal_disc: ShaderMaterial
var portal_follows := false                 # false: it stays where it is; true: it rides on the end of the forearm
var portal_size := 0.0
var portal_tween: Tween


func _find_model_root() -> Node3D:
	return $HandModel


func _find_anim() -> AnimationPlayer:
	return $HandModel/AnimationPlayer


func _find_model() -> MeshInstance3D:
	return $HandModel/HandBoss/Skeleton3D/HandBossMesh


func _setup_navigation() -> void:
	nav.avoidance_enabled = false   # it moves itself; EnemyBase needs the agent to exist


func _keeps_to_navmesh() -> bool:
	return false


func get_state_definitions() -> Dictionary:
	# The fight runs in _brain(); these only satisfy EnemyBase
	return {"Idle": HandState.new(), "Dead": HandState.new()}


class HandState:
	pass


func _ready() -> void:
	model_root.scale = Vector3.ONE * hand_scale
	super()
	max_health = health
	blood_scale = 2.5
	home = global_position
	floor_y = global_position.y   # measured properly on waking: the map's collision may not exist yet
	skeleton = $HandModel/HandBoss/Skeleton3D
	skin = ShaderMaterial.new()
	skin.shader = HAND_SHADER
	model.material_override = skin
	_measure()
	_build_hurtboxes()
	_build_body_shape()
	_build_portal()
	health_bar = get_tree().current_scene.find_child("BossHealthBar", true, false) as Control
	if health_bar:
		health_bar.set_max_health(health)
		health_bar.set_health(health)
		if health_bar.has_method("set_boss_name"):
			health_bar.set_boss_name(boss_name)
	# Out of sight and out of reach until the entrance
	model_root.visible = false
	portal.visible = false
	_set_layers_enabled(false)


# Wave triggers take their enemies out of the level a few frames after it loads, and a respawn can put the player
# within wake_distance before that: so it settles in for a moment before it can wake (see also _go_dormant).
const WAKE_SETTLE_FRAMES := 6   # process frames, like the wave trigger's wait: a loading hitch is one of them


func _enter_tree() -> void:
	frames_in_level = 0


func _physics_process(delta: float) -> void:
	super(delta)
	if not awake and not destroyed and frames_in_level > WAKE_SETTLE_FRAMES and _target_here():
		if flat_distance(target.global_position, global_position) <= wake_distance:
			awake = true
			_brain()


func _process(_delta: float) -> void:
	frames_in_level += 1
	_update_portal()


# ---------------------------------------------------------------------------------------------------- measuring

func bone_index(bone: String) -> int:
	return skeleton.find_bone(bone)


# Where a bone starts (its joint), in the world
func bone_head(bone: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index(bone)).origin


# Where a bone ends: the next joint, or for a fingertip the same distance on as the bone's length
func bone_tip(bone: String) -> Vector3:
	var index := bone_index(bone)
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	return pose.origin + pose.basis.y.normalized() * bone_length(bone) * hand_scale


# Length of a bone in model units, from the rest pose
func bone_length(bone: String) -> float:
	if bone == "hand":
		return skeleton.get_bone_rest(bone_index("middle_1")).origin.length()   # wrist to the middle knuckle
	var index := bone_index(bone)
	for child in skeleton.get_bone_children(index):
		var child_name := skeleton.get_bone_name(child)
		if child_name.begins_with(bone.split("_")[0]) or bone == "forearm":
			return skeleton.get_bone_rest(child).origin.length()
	# A fingertip: about three quarters of the bone before it
	var parent := skeleton.get_bone_parent(index)
	return skeleton.get_bone_rest(index).origin.length() * 0.75 if parent >= 0 else 1.0


func _measure() -> void:
	hand_length = bone_tip("middle_3").distance_to(bone_head("hand"))
	forearm_length = bone_head("forearm").distance_to(bone_head("hand"))
	palm_half_width = bone_head("pinky_1").distance_to(bone_head("index_1")) * 0.5 + 0.6 * hand_scale


func size() -> float:
	return hand_scale


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func floor_point(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 60.0)
	query.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3(point.x, floor_y, point.z)
	return Vector3(point.x, hit["position"].y, point.z)


# The player exists and is still in the level (not mid-reload after dying)
func _target_here() -> bool:
	return is_instance_valid(target) and target.is_inside_tree()


func target_floor() -> Vector3:
	return Vector3(target.global_position.x, floor_y, target.global_position.z) if _target_here() else home


# A point kept inside the arena (a little in from its wall)
func in_arena(point: Vector3, margin := 3.0) -> Vector3:
	var offset := flat(point - home)
	return home + offset.limit_length(arena_radius - margin) + Vector3.UP * (point.y - home.y)


# The hand's orientation with its fingers pointing one way and its palm facing another. The model's rest pose has
# the fingers along -Z and the palm facing -Y.
static func hand_basis(fingers: Vector3, palm: Vector3) -> Basis:
	var z := -fingers.normalized()
	var y := -palm
	y = y - z * y.dot(z)
	if y.length() < 0.01:
		y = Vector3.UP if absf(z.y) < 0.9 else Vector3.FORWARD
	y = y.normalized()
	return Basis(y.cross(z), y, z).orthonormalized()


# Hanging fingers-down with the back of the hand to the player, as in the reference picture
func hanging_basis() -> Basis:
	var away := flat(global_position - target.global_position) if _target_here() else Vector3.FORWARD
	if away.length() < 0.1:
		away = Vector3.FORWARD
	return hand_basis(Vector3.DOWN, away.normalized())


# A point on the hand (in the current pose), relative to the wrist
func local_point(world: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world


# Where the wrist goes so that a point on the hand (from local_point) lands on `world`, with the hand turned to `basis`
func wrist_for(point_local: Vector3, world: Vector3, basis: Basis) -> Vector3:
	return world - basis * point_local


# How far below the wrist the hand reaches in the current pose, turned to `basis` (fingertips and joints)
func reach_below(basis: Basis) -> float:
	var lowest := 0.0
	var inverse := global_transform.affine_inverse()
	for finger in FINGERS:
		for i in [1, 2, 3]:
			var bone := "%s_%d" % [finger, i]
			for point in [bone_head(bone), bone_tip(bone)]:
				lowest = minf(lowest, (basis * (inverse * point)).y)
	return -lowest + 0.35 * hand_scale   # the finger's thickness


# ------------------------------------------------------------------------------------------------- building bits

# Hurtboxes for the player's weapons: a capsule along every bone, a box for the palm
func _build_hurtboxes() -> void:
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		var attach := BoneAttachment3D.new()
		attach.bone_name = bone
		skeleton.add_child(attach)
		var area := Area3D.new()
		area.collision_layer = 8
		area.collision_mask = 0
		area.monitoring = false
		area.set_script(HURTBOX_SCRIPT)
		area.set("owner_enemy", self)
		attach.add_child(area)
		var shape := CollisionShape3D.new()
		var length := bone_length(bone)
		if bone == "hand":
			var box := BoxShape3D.new()
			box.size = Vector3(2.3, length, 0.6)
			shape.shape = box
		else:
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.95 if bone == "forearm" else (0.36 if bone.begins_with("thumb") else 0.3)
			capsule.height = maxf(length + capsule.radius, capsule.radius * 2.0 + 0.01)
			shape.shape = capsule
		shape.position = Vector3(0.0, length * 0.5, 0.0)
		area.add_child(shape)
		hurtboxes[bone] = area


# The solid part: a capsule from the wrist to the knuckles, so the player can stand on a planted hand and a
# parried orb has something to hit
func _build_body_shape() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var knuckles := local_point(bone_head("middle_1"))
	capsule.radius = 1.6 * hand_scale * 0.4
	capsule.height = knuckles.length() + capsule.radius * 2.0
	shape.shape = capsule
	shape.position = knuckles * 0.5
	shape.basis = Basis(Quaternion(Vector3.UP, knuckles.normalized()))
	add_child(shape)


func _set_layers_enabled(enabled: bool) -> void:
	collision_layer = 4 if enabled else 0
	for area in hurtboxes.values():
		area.collision_layer = 8 if enabled else 0


# The portal the forearm comes out of: a ragged tear onto a dark dimension (shaders/boss/dark_portal.gdshader), lying
# across the forearm, with dark smoke curling out of its edge and only a dim violet light. Its local +Y points
# into the dark side.
func _build_portal() -> void:
	portal = Node3D.new()
	portal.name = "Portal"
	portal.top_level = true
	add_child(portal)
	portal_size = 0.62 * hand_scale * 3.6   # radius of the opening: about twice the forearm's
	portal_disc = ShaderMaterial.new()
	portal_disc.shader = PORTAL_SHADER
	portal_disc.set_shader_parameter("open_amount", 0.0)
	portal_disc.render_priority = 20   # after the synthwave sky, which is see-through geometry and would cover it
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * portal_size * 2.0 / 0.8   # the shader's edge sits at 0.8 of the plane's half-size
	var disc := MeshInstance3D.new()
	disc.mesh = plane
	disc.material_override = portal_disc
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal.add_child(disc)
	portal.add_child(_portal_smoke())
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.15, 1.0)
	light.omni_range = portal_size * 3.0
	light.light_energy = 0.8
	light.position = Vector3.DOWN * 1.5
	portal.add_child(light)


# Dark wisps leaking out of the tear's edge and drifting away on this side
func _portal_smoke() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = portal_size * 1.0
	process.emission_ring_inner_radius = portal_size * 0.75
	process.emission_ring_height = 0.2
	process.direction = Vector3.DOWN
	process.spread = 35.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.8
	process.gravity = Vector3.ZERO
	process.damping_min = 0.3
	process.damping_max = 0.8
	process.scale_min = 0.7
	process.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(0.05, 0.0, 0.1, 0.0), Color(0.04, 0.0, 0.08, 0.7), Color(0.02, 0.0, 0.05, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp

	var puff := GradientTexture2D.new()
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	puff.gradient = dot
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = puff
	material.render_priority = 19
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * portal_size * 0.7
	quad.material = material

	var smoke := GPUParticles3D.new()
	smoke.amount = 36
	smoke.lifetime = 2.6
	smoke.local_coords = false   # wisps left behind trail off as the portal moves
	smoke.process_material = process
	smoke.draw_pass_1 = quad
	smoke.visibility_aabb = AABB(Vector3.ONE * -portal_size * 4.0, Vector3.ONE * portal_size * 8.0)
	return smoke


func set_portal_open(amount: float, seconds: float) -> Tween:
	if portal_tween != null and portal_tween.is_valid():
		portal_tween.kill()
	var tween := create_tween()
	portal_tween = tween
	tween.tween_method(func(v: float): portal_disc.set_shader_parameter("open_amount", v),
			float(portal_disc.get_shader_parameter("open_amount")), amount, seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if amount > 0.5 else Tween.EASE_IN)
	return tween


# The portal lies across the forearm just short of its cut-off end, and everything past it is not drawn
func _update_portal() -> void:
	if portal == null or skeleton == null:
		return
	if portal_follows:
		var elbow := bone_head("forearm")
		var wrist := bone_head("hand")
		var out := (elbow - wrist).normalized()
		portal.global_transform = Transform3D(_basis_with_up(out), elbow - out * 0.35 * hand_scale)
	var normal := portal.global_basis.y.normalized()
	skin.set_shader_parameter("clip_plane", Vector4(normal.x, normal.y, normal.z, normal.dot(portal.global_position)))


static func _basis_with_up(up: Vector3) -> Basis:
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()


# ---------------------------------------------------------------------------------------------------- the look

var glow_color := DANGER_GLOW
var glow_amount := 0.0


func set_glow(color: Color, amount: float, seconds := 0.3) -> void:
	if glow_tween != null and glow_tween.is_valid():
		glow_tween.kill()
	glow_color = color
	skin.set_shader_parameter("glow_color", color)
	glow_tween = create_tween()
	glow_tween.tween_method(_apply_glow, glow_amount, amount, maxf(seconds, 0.01))


func _apply_glow(amount: float) -> void:
	glow_amount = amount
	skin.set_shader_parameter("glow_amount", amount)


func glow_off(seconds := 0.4) -> void:
	set_glow(glow_color, 0.0, seconds)


func pose(clip: String, blend := 0.2, speed := 1.0) -> void:
	if anim.has_animation(clip):
		anim.play(clip, blend, speed)


func play_sfx(paths: String) -> void:
	Audio.play(paths)


func shake_player_camera(pitch: float, yaw: float) -> void:
	if is_instance_valid(target) and target.has_method("apply_camera_kick"):
		target.apply_camera_kick(pitch, randf_range(-yaw, yaw))


func rattle_player_camera(trauma: float) -> void:
	if is_instance_valid(target) and target.has_method("add_camera_shake"):
		target.add_camera_shake(trauma)


func warn_circle(center: Vector3, radius: float, color := WARN_COLOR) -> BossTelegraph:
	var warning := BossTelegraph.circle(get_tree(), center, radius, color)
	action_fx.append(warning)
	return warning


func warn_lane(from: Vector3, to: Vector3, width: float, color := WARN_COLOR) -> BossTelegraph:
	var warning := BossTelegraph.lane(get_tree(), from, to, width, color)
	action_fx.append(warning)
	return warning


func set_weak_points(knuckles: bool, palm: bool) -> void:
	knuckles_exposed = knuckles
	palm_open = palm
	for finger in FINGERS:
		hurtboxes["%s_1" % finger].set("multiplier", crit_multiplier if knuckles else 1.0)
	hurtboxes["hand"].set("multiplier", crit_multiplier if palm else 1.0)


# --------------------------------------------------------------------------------------------- moving (coroutines)

func _ease(t: float, curve: Ease) -> float:
	match curve:
		Ease.IN:
			return t * t * t
		Ease.OUT:
			return 1.0 - pow(1.0 - t, 3.0)
		Ease.LINEAR:
			return t
	return t * t * (3.0 - 2.0 * t)


# Waits, unless the hand is interrupted first. Returns false if it was.
func wait(seconds: float) -> bool:
	return await track(seconds, func(_t: float, _dt: float): pass)


# Moves the wrist to `to` over `seconds`. Returns false if interrupted.
func glide(to: Transform3D, seconds: float, curve := Ease.SMOOTH) -> bool:
	if not is_inside_tree():
		return false
	var from := global_transform
	seconds = maxf(seconds, 0.01)
	return await track(seconds, func(t: float, _dt: float):
		global_transform = from.interpolate_with(to, _ease(minf(t / seconds, 1.0), curve)))


# Calls step(elapsed, delta) every physics frame for `seconds`. Returns false if interrupted.
func track(seconds: float, step: Callable) -> bool:
	var token := action_token
	var elapsed := 0.0
	while elapsed < seconds:
		if not is_inside_tree():
			return false   # the level is being reloaded (the player died): stop without touching the transform
		await get_tree().physics_frame
		if token != action_token or not is_inside_tree():
			return false
		if not can_process():
			continue   # the game is paused: the physics_frame signal still fires, so hold still
		var delta := get_physics_process_delta_time()
		elapsed += delta
		step.call(elapsed, delta)
	return true


# Eases the wrist part of the way towards a transform: for following something every frame
func steer(to: Transform3D, delta: float, rate := 4.0) -> void:
	global_transform = global_transform.interpolate_with(to, 1.0 - exp(-rate * delta))


func hover_transform() -> Transform3D:
	var player := target_floor()
	var spot := home + flat(player - home).limit_length(arena_radius * 0.35)
	spot.y = floor_y + hand_length + hover_clearance
	var away := flat(spot - player)
	if away.length() < 0.5:
		away = flat(spot - home) if flat(spot - home).length() > 0.5 else Vector3.FORWARD
	return Transform3D(hand_basis(Vector3.DOWN, away.normalized()), spot)


func hover(seconds: float) -> bool:
	if not is_inside_tree():
		return false
	pose("Hover", 0.4)
	return await track(seconds, func(_t: float, dt: float): steer(hover_transform(), dt, 2.0))


func speed() -> float:
	return float(PHASES[phase - 1]["speed"])


# ------------------------------------------------------------------------------------------------- hurting things

func player_height() -> float:
	return target.global_position.y - floor_y if _target_here() else INF


func hurt_player(amount: float, push: Vector3) -> void:
	if not is_instance_valid(target):
		return
	if target.has_method("damage"):
		target.damage(amount, false, self)
	if target.has_method("apply_push") and push.length() > 0.01:
		target.apply_push(push)
	shake_player_camera(0.08, 0.03)


# Is the player inside the footprint of the hand lying flat: from `back` behind the wrist to `front` ahead of it
# along `along`, and `half_width` to either side?
func in_footprint(wrist: Vector3, along: Vector3, back: float, front: float, half_width: float) -> bool:
	if not is_instance_valid(target):
		return false
	var offset := flat(target.global_position - wrist)
	var a := along.normalized()
	var forward := offset.dot(a)
	var side := absf(offset.dot(Vector3.UP.cross(a).normalized()))
	return forward >= -back and forward <= front and side <= half_width


# ------------------------------------------------------------------------------------------------------- the brain

func _brain() -> void:
	var placed := transform
	await _fight()
	# Taken out of the level part-way through: a wave trigger holding the boss back caught it after it woke (on a
	# respawn the player is put back within wake_distance before the trigger has collected its wave). Go back to
	# sleep where it was placed, so it wakes and makes its entrance again once the trigger lets it back in.
	if not destroyed and not is_inside_tree():
		_go_dormant(placed)


func _go_dormant(placed: Transform3D) -> void:
	awake = false
	action_token += 1   # anything still awaiting gives up
	pending_reaction = ""
	for warning in action_fx:
		if is_instance_valid(warning):
			warning.finish(0.15)
	action_fx.clear()
	parryable = false
	invulnerable = true
	set_weak_points(false, false)
	if glow_tween != null and glow_tween.is_valid():
		glow_tween.kill()
	_apply_glow(0.0)
	if portal_tween != null and portal_tween.is_valid():
		portal_tween.kill()
	portal_disc.set_shader_parameter("open_amount", 0.0)
	transform = placed   # local: the global transform can't be set out of the tree
	model_root.visible = false
	portal.visible = false
	portal_follows = false
	_set_layers_enabled(false)
	if health_bar and health_bar.has_method("hide_bar"):
		health_bar.hide_bar()


func _fight() -> void:
	home = global_position
	floor_y = global_position.y
	floor_y = floor_point(global_position).y
	home.y = floor_y
	await _entrance()
	while not destroyed and is_inside_tree():
		_end_action()
		if pending_reaction != "":
			var reaction := pending_reaction
			pending_reaction = ""
			await _react(reaction)
			continue
		var attack := _choose_attack()
		if attack.is_empty():
			await hover(0.4)
			continue
		await _run_attack(attack)
		if destroyed or not is_inside_tree():
			return
		if pending_reaction.is_empty():
			_end_action()
			await hover(float(PHASES[phase - 1]["gap"]) * randf_range(0.85, 1.2))


func _choose_attack() -> String:
	var now := Time.get_ticks_msec()
	var options: Array[String] = []
	for attack in PHASES[phase - 1]["attacks"]:
		if now < int(cooldown_until.get(attack, 0)):
			continue
		options.append(attack)
	if options.is_empty():
		return ""
	var pick: String = options.pick_random()
	cooldown_until[pick] = now + int(COOLDOWNS[pick] / speed() * randf_range(0.85, 1.15) * 1000.0)
	return pick


# Stops whatever the hand is doing and runs a reaction next: "stagger", "stuck" or "transition"
func interrupt(reaction: String) -> void:
	if destroyed:
		return
	if pending_reaction == "transition":
		return   # a phase change wins over anything else
	pending_reaction = reaction
	action_token += 1


# Tidies up after an action, however it ended
func _end_action() -> void:
	for warning in action_fx:
		if is_instance_valid(warning):
			warning.finish(0.15)
	action_fx.clear()
	parryable = false
	vulnerability = 1.0
	set_weak_points(false, false)
	glow_off()
	anim.speed_scale = 1.0


func _run_attack(attack: String) -> void:
	match attack:
		"slam":
			await _attack_slam()
		"poke":
			await _attack_poke()
		"flick":
			await _attack_flick()
		"sweep":
			await _attack_sweep()
		"mortar":
			await _attack_mortar()
		"spokes":
			await _attack_spokes()
		"crush":
			await _attack_crush()


func _react(reaction: String) -> void:
	match reaction:
		"stagger":
			await _stagger()
		"stuck":
			await _stuck()
		"transition":
			await _transition()


# ------------------------------------------------------------------------------------------------------- entrance

func _entrance() -> void:
	invulnerable = true
	var portal_point := home + Vector3.UP * portal_height
	portal.global_transform = Transform3D(Basis.IDENTITY, portal_point)
	portal.visible = true
	portal_follows = false
	set_portal_open(1.0, 0.4)   # the tear rips open
	play_sfx(SFX_ROAR)
	rattle_player_camera(0.5)

	# Starts fully above the portal (so none of it is drawn) as a clenched fist
	pose("Fist", 0.0)
	var basis := hanging_basis()
	global_transform = Transform3D(basis, portal_point + Vector3.UP * (hand_length + 1.0))
	model_root.visible = true
	if not await wait(entrance_windup):
		return
	# Measured once the fist pose is on: where the knuckles are on the hand, and the wrist height that puts the
	# lowest of them on the water (as in the slam)
	var knuckles := local_point(bone_head("middle_2"))
	var planted_y := floor_y + reach_below(basis) - 0.2
	var impact := home + flat(target_floor() - home).limit_length(arena_radius * 0.25)
	var end_origin := wrist_for(knuckles, impact, basis)
	end_origin.y = planted_y
	var end := Transform3D(basis, end_origin)
	var start := global_position
	# Punches down through the portal, gathering speed all the way to the water
	var ok := await track(entrance_time, func(t: float, _dt: float):
		var k := _ease(minf(t / entrance_time, 1.0), Ease.IN)
		global_transform = Transform3D(basis, start.lerp(end.origin, k))
		# The portal lets go of the sky once the forearm's end has come through it
		if not portal_follows and bone_head("forearm").y <= portal.global_position.y:
			portal_follows = true)
	if not ok:
		return
	global_transform = end
	portal_follows = true

	# The impact: a wave of water out from the fist that shoves the player back (no damage), and a big jolt
	BossShockwave.spawn(get_tree(), impact, arena_radius * 0.7, 1.6 * hand_length, 0.0, true)
	WaterRipple.spawn(get_tree(), impact, 1.5, 6.0)
	BossDust.spawn(get_tree(), impact, 1.6)
	ImpactParticles.spawn(get_tree(), impact + Vector3.UP * 0.3, Vector3.UP, 3.5)
	play_sfx(SFX_HIT)
	play_sfx(SFX_ROAR)
	rattle_player_camera(0.9)
	shake_player_camera(0.16, 0.05)
	_set_layers_enabled(true)
	invulnerable = false
	if health_bar:
		health_bar.show_bar()
	if not await wait(0.5):
		return
	pose("Release", 0.2)
	await glide(hover_transform(), 0.7)


# ------------------------------------------------------------------------------------------------------- attacks

# Clenches over the player, follows them, then drops onto them: a shockwave runs out from the fist, and the fist
# stays planted for a moment with its knuckles exposed.
func _attack_slam() -> void:
	pose("Clench", 0.15)
	anim.queue("FistTremble")
	set_glow(DANGER_GLOW, 0.8, 0.4)
	if not await wait(0.4):
		return
	var radius := 0.42 * hand_length
	var basis := hanging_basis()
	# The wrist height at which the fist's lowest knuckles touch the floor, and the knuckles' place on the hand
	var planted_y := floor_y + reach_below(basis) - 0.2
	var knuckles := local_point(bone_head("middle_2"))
	var warning := warn_circle(target_floor(), radius)
	var track_time := slam_track_time / speed()
	var aim := [target_floor()]
	var ok := await track(track_time, func(t: float, dt: float):
		aim[0] = aim[0].lerp(in_arena(target_floor()), 1.0 - exp(-5.0 * dt))
		warning.global_position = aim[0] + Vector3.UP * BossTelegraph.FLOOR_LIFT
		warning.set_progress(t / (track_time + 0.3))
		var wrist := wrist_for(knuckles, aim[0], basis)
		steer(Transform3D(basis, Vector3(wrist.x, planted_y + 5.0, wrist.z)), dt, 6.0))
	if not ok:
		return
	if not await wait(0.3):
		return
	# Drop so the knuckles meet the floor
	var drop_to := wrist_for(knuckles, aim[0], basis)
	drop_to.y = planted_y
	if not await glide(Transform3D(basis, drop_to), 0.2 / speed(), Ease.IN):
		return
	var impact: Vector3 = aim[0]
	BossShockwave.spawn(get_tree(), impact, 0.95 * hand_length, 1.6 * hand_length, slam_damage)
	BossDust.spawn(get_tree(), impact, 1.2)
	ImpactParticles.spawn(get_tree(), impact + Vector3.UP * 0.3, Vector3.UP, 3.0)
	play_sfx(SFX_HIT)
	rattle_player_camera(0.8)
	shake_player_camera(0.12, 0.04)
	if is_instance_valid(target) and flat_distance(target.global_position, impact) <= radius * 0.6 and player_height() < 2.0:
		hurt_player(slam_damage, flat(target.global_position - impact).normalized() * 22.0)
	warning.finish(0.1)
	# Planted: the knuckles are the weak point
	set_weak_points(true, false)
	set_glow(WEAK_GLOW, 0.6, 0.2)
	pose("Fist", 0.1)
	if not await wait(slam_hold / speed()):
		return
	set_weak_points(false, false)
	glow_off(0.2)
	pose("Release", 0.15)
	await glide(hover_transform(), 0.45, Ease.OUT)   # wrenches itself back up out of the floor


const POKE_PACE := 1.25   # the whole jab sequence runs this much faster than its timings below (20% less time)


# Three jabs of the index finger at where the player is standing. The third glows yellow: parry it and the finger
# sticks in the floor.
func _attack_poke() -> void:
	var pace := speed() * POKE_PACE
	pose("Point", 0.2)
	if not await wait(0.35 / POKE_PACE):
		return
	var tip_local := local_point(bone_tip("index_3"))
	for jab in 3:
		var last := jab == 2
		var spot := in_arena(target_floor())
		if is_instance_valid(target) and "velocity" in target:
			spot = in_arena(spot + flat(target.velocity) * 0.25)
		var basis := hanging_basis()
		var warn_time := (poke_warn + (0.2 if last else 0.0)) / pace
		var warning := warn_circle(spot, poke_radius, PARRY_GLOW if last else WARN_COLOR)
		var above := Transform3D(basis, wrist_for(tip_local, spot + Vector3.UP * 7.0, basis))
		set_glow(PARRY_GLOW if last else DANGER_GLOW, 0.9 if last else 0.7, warn_time)
		var ok := await track(warn_time, func(t: float, dt: float):
			warning.set_progress(t / warn_time)
			steer(above, dt, 7.0 * POKE_PACE))
		if not ok:
			return
		parryable = last
		if not await glide(Transform3D(basis, wrist_for(tip_local, spot + Vector3.UP * 0.2, basis)), 0.13 / pace, Ease.IN):
			return
		warning.finish(0.1)
		ImpactParticles.spawn(get_tree(), spot + Vector3.UP * 0.2, Vector3.UP, 1.6)
		BossDust.spawn(get_tree(), spot, 0.5)
		play_sfx(SFX_HIT)
		# A jolt down as it lands, then a rattle that dies away: harder on the last jab
		shake_player_camera(0.1 if last else 0.07, 0.03)
		rattle_player_camera(0.6 if last else 0.45)
		# The jab has landed: from here on it is too late to parry it
		parryable = false
		if is_instance_valid(target) and flat_distance(target.global_position, spot) <= poke_radius and player_height() < 2.0:
			hurt_player(poke_damage, flat(target.global_position - spot).normalized() * 16.0)
		if not await _press_into_floor(spot, basis, (0.5 if last else 0.28) / pace):
			return
		parryable = false
		glow_off(0.15)
		# Springs back off the floor
		pose("Point", 0.08)
		if not await glide(Transform3D(basis, wrist_for(tip_local, spot + Vector3.UP * 7.0, basis)), 0.3 / pace, Ease.OUT):
			return
	await glide(hover_transform(), 0.6 / POKE_PACE)


# A jab meeting resistance: the fingertip stays pinned to the floor while the finger buckles (PokePress) and the
# hand sinks onto it, leaning and shuddering about the tip, the shudder dying away. `seconds` is how long it
# stays down (the last jab stays longer: the window to parry the finger). Returns false if interrupted.
func _press_into_floor(spot: Vector3, basis: Basis, seconds: float) -> bool:
	var pinned := spot + Vector3.UP * 0.2
	var sideways := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var lean_axis := Vector3.UP.cross(sideways.normalized() if sideways.length() > 0.1 else Vector3.RIGHT).normalized()
	var lean_sign := 1.0 if randf() < 0.5 else -1.0
	pose("PokePress", 0.07)
	WaterRipple.spawn(get_tree(), spot, 0.45, 2.5)
	return await track(seconds, func(t: float, _dt: float):
		var k := minf(t / seconds, 1.0)
		var push := sin(minf(k * 3.0, 1.0) * PI * 0.5)        # sinks in fast, then holds against it
		var shudder := sin(t * 38.0) * (1.0 - k) * 2.5          # degrees, dying away
		var lean := Basis(lean_axis, deg_to_rad((push * 6.0 + shudder) * lean_sign))
		var twist := Basis(Vector3.UP, deg_to_rad(sin(t * 23.0) * (1.0 - k) * 2.0))
		var pressed := (twist * lean * basis).orthonormalized()
		# Keep the tip where it is: the bending finger lets the hand come down onto it
		var tip_now := local_point(bone_tip("index_3"))
		global_transform = Transform3D(pressed, wrist_for(tip_now, pinned, pressed)))


# Where a parried orb homes to (energy_ball.gd): the middle of the palm, wherever the hand has moved to
func reflect_aim_point() -> Vector3:
	return bone_head("hand").lerp(bone_head("middle_1"), 0.55)


# Where the player's shield checks a parry from: the tip of the jabbing finger
func parry_point() -> Vector3:
	return bone_tip("index_3")


# The shield caught the third jab
func on_parried() -> void:
	if not parryable or destroyed:
		return
	parryable = false
	interrupt("stuck")


# Faces the player with its index finger hooked under the thumb, strains, then flicks a big yellow orb at them.
# Parried back into the hand, the orb staggers it.
func _attack_flick() -> void:
	pose("FlickHold", 0.25)
	set_glow(PARRY_GLOW, 0.5, flick_charge)
	var charge := flick_charge / speed()
	var ok := await track(charge, func(_t: float, dt: float): steer(_flick_transform(), dt, 3.0))
	if not ok:
		return
	pose("FlickRelease", 0.05)
	if not await wait(0.1):
		return
	# The orb's homing weakens with speed (energy_ball.gd), so the turn rate scales with it to curve the same
	_fire_orb(bone_tip("index_3"), flick_damage, flick_orb_speed, 4.5, 0.8 * flick_orb_speed / 11.0, 9.0)
	shake_player_camera(0.04, 0.02)
	glow_off()
	if not await wait(0.7):
		return
	await glide(hover_transform(), 0.8)


func _flick_transform() -> Transform3D:
	var player := target_floor()
	var from_player := flat(home - player)
	if from_player.length() < 1.0:
		from_player = flat(global_position - player)
	from_player = from_player.normalized() if from_player.length() > 0.1 else Vector3.FORWARD
	var spot := in_arena(player + from_player * 20.0, 5.0)
	spot.y = floor_y + 7.0
	var to_player := (player + Vector3.UP * 1.5 - spot).normalized()
	var basis := hand_basis(to_player, Vector3.DOWN)
	return Transform3D(basis, spot - basis * Vector3(0.0, 0.0, -hand_length * 0.35))


func _fire_orb(origin: Vector3, damage_amount: float, speed_value: float, max_size: float, turn: float, life: float) -> void:
	if not is_instance_valid(target):
		return
	var ball = ENERGY_BALL.instantiate()
	ball.damage = damage_amount
	ball.SPEED = speed_value
	ball.max_scale = max_size
	ball.scale_speed = 2.0
	ball.turn_rate = turn
	ball.shooter = self
	ball.always_return_to_shooter = true
	ball.get_node("SelfQueueTimer").wait_time = life
	get_tree().current_scene.add_child(ball)
	ball.global_position = origin
	ball.velocity = (target.global_position + Vector3.UP - origin).normalized() * speed_value
	if turn > 0.0:
		ball.set_target(target)
	Audio.play_at(origin, SFX_SHOOT)


# A parried orb came back. The flick's big orb staggers it.
func on_reflected_orb_hit(orb_damage: float) -> void:
	if destroyed or invulnerable:
		return
	if orb_damage >= flick_damage * 1.5:
		play_sfx(SFX_HIT)
		shake_player_camera(0.05, 0.02)
		_lose_health(max_health * flick_reflect_fraction)
		if not destroyed:
			interrupt("stagger")
	else:
		_lose_health(orb_damage * 2.0)


# Lays flat at one side of the arena and wipes across it. The fingers drag lowest: jump them.
func _attack_sweep() -> void:
	pose("Flat", 0.3)
	set_glow(DANGER_GLOW, 0.8, 0.5)
	var player := target_floor()
	var across := flat(player - home)
	across = across.normalized() if across.length() > 1.0 else Vector3.RIGHT
	var travel := Vector3.UP.cross(across).normalized() * (1.0 if randf() < 0.5 else -1.0)
	# The wrist runs along a line that puts the middle of the fingers over the player
	var line_point := player - across * hand_length * 0.55
	var reach := arena_radius * 0.95
	var start := line_point - travel * reach
	var finish := line_point + travel * reach
	var basis := hand_basis(across, Vector3.DOWN)
	if not await wait(0.3):
		return
	var low := floor_y + reach_below(basis) - 0.15
	var footprint_mid := (hand_length - forearm_length) * 0.5
	var lane := warn_lane(start + across * footprint_mid, finish + across * footprint_mid, hand_length + forearm_length)
	var up_start := Transform3D(basis, Vector3(start.x, low + 8.0, start.z))
	var warn_time := 1.4 / speed()
	var ok := await track(warn_time, func(t: float, dt: float):
		lane.set_progress(t / warn_time)
		var target_xform := up_start if t < warn_time * 0.55 else Transform3D(basis, Vector3(start.x, low, start.z))
		steer(target_xform, dt, 5.0))
	if not ok:
		return
	global_transform = Transform3D(basis, Vector3(start.x, low, start.z))
	lane.finish(0.2)
	play_sfx(SFX_ROAR)
	# In the last phase the hand turns round at the far side and wipes back the way it came: two passes to dodge
	var legs: Array = [[start, finish]]
	if phase >= 3:
		legs.append([finish, start])
	for leg_index in legs.size():
		var from_point: Vector3 = legs[leg_index][0]
		var to_point: Vector3 = legs[leg_index][1]
		if leg_index > 0:
			var back_lane := warn_lane(from_point + across * footprint_mid, to_point + across * footprint_mid, hand_length + forearm_length)
			var turn := 0.7 / speed()
			if not await track(turn, func(t: float, _dt: float): back_lane.set_progress(t / turn)):
				return
			back_lane.finish(0.2)
			play_sfx(SFX_ROAR)
		var hit := [false]
		var time := sweep_time / speed()
		var pass_direction := flat(to_point - from_point).normalized()
		ok = await track(time, func(t: float, _dt: float):
			var k := _ease(minf(t / time, 1.0), Ease.SMOOTH)
			var wrist := from_point.lerp(to_point, k)
			global_transform = Transform3D(basis, Vector3(wrist.x, low, wrist.z))
			if int(t * 30.0) % 3 == 0:
				ImpactParticles.spawn(get_tree(), Vector3(wrist.x, floor_y + 0.2, wrist.z) + across * hand_length * 0.6, -pass_direction, 0.8)
			if not hit[0] and player_height() < sweep_clearance and in_footprint(wrist, across, forearm_length, hand_length, palm_half_width):
				hit[0] = true
				hurt_player(sweep_damage, pass_direction * 26.0 + Vector3.UP * 4.0))
		if not ok:
			return
	glow_off()
	if not await wait(0.4):
		return
	await glide(hover_transform(), 0.9)


# Holds the hand up with its fingers spread and lobs a mortar shell from every fingertip, in waves. Each shell goes
# straight up out of sight and comes down a moment later on a spot marked on the floor, splashing everyone in the red
# circle. The first shell of a wave lands on the player; the rest land scattered round them. They can't be parried.
func _attack_mortar() -> void:
	pose("Spread", 0.3)
	set_glow(DANGER_GLOW, 0.6, 0.8)
	set_weak_points(false, true)
	var ok := await track(0.9 / speed(), func(_t: float, dt: float): steer(_mortar_transform(), dt, 3.0))
	if not ok:
		return
	var waves := mortar_waves + (1 if phase >= 3 else 0)
	for wave in waves:
		pose("VolleyRecoil", 0.05)
		var tips: Array[Vector3] = []
		for finger in FINGERS + ["thumb"]:
			tips.append(bone_tip("thumb_2" if finger == "thumb" else "%s_3" % finger))
		var player := target_floor()
		for i in tips.size():
			var spot := player
			if i > 0:
				var angle := randf() * TAU
				spot = player + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(mortar_scatter * 0.35, mortar_scatter)
			spot = in_arena(spot, 1.0)
			spot.y = floor_y
			HandMortar.launch(self, tips[i], spot, mortar_radius, mortar_rise, mortar_fall)
			if i == 0:
				play_sfx(SFX_SHOOT)
		shake_player_camera(0.02, 0.01)
		ok = await track((mortar_fall * 0.6 + 0.4) / speed(), func(_t: float, dt: float): steer(_mortar_transform(), dt, 3.0))
		if not ok:
			return
	# The last wave is still in the air: hold on until it has come down
	if not await track(mortar_rise + mortar_fall, func(_t: float, dt: float): steer(_mortar_transform(), dt, 3.0)):
		return
	set_weak_points(false, false)
	glow_off()
	await glide(hover_transform(), 0.8)


# A shell landed: hurts the player if they are inside its circle, harder nearer the middle
func splash(center: Vector3, radius: float) -> void:
	play_sfx(SFX_HIT)
	rattle_player_camera(0.3)
	if not is_instance_valid(target) or player_height() > 2.5:
		return
	var distance := flat_distance(target.global_position, center)
	if distance > radius:
		return
	var push := flat(target.global_position - center).normalized() * 12.0 + Vector3.UP * 3.0
	hurt_player(mortar_damage * Blast.falloff(distance, radius), push)


func _mortar_transform() -> Transform3D:
	var player := target_floor()
	var from_player := flat(global_position - player)
	from_player = from_player.normalized() if from_player.length() > 0.5 else Vector3.FORWARD
	var spot := in_arena(player + from_player * 18.0, 4.0)
	spot.y = floor_y + 3.0
	var to_player := flat(player - spot).normalized()
	return Transform3D(hand_basis(Vector3.UP, to_player), spot)


# The hand hangs palm-down over the middle of the arena and lights up wedges of the floor that fan out from under it
# like spokes: four at a time, a quarter turn apart. Each wedge fills red, then ignites into a wall of fire (the same
# columns the robot boss's floor hazard raises) that surges out along it and burns for a moment, hurting anyone on the
# ground inside it; jumping clears a tick. Then the hand turns and lights a different four. Every other set is aimed
# so that one wedge lands on wherever the player is standing, so there is no spot to camp in and no edge to retreat
# to: the safe ground is always between the spokes, and it moves.
#
# How the hand moves (clips from tools/assetgen/hand_boss.py): it rises clenched and trembling, then FanBloom snaps it
# open into a fan. While a set charges, FanWave ripples through the fingers and the hand glows brighter; when the
# fire ignites FanStrike slaps the fingers flat, the hand dips and flashes white-hot, and it turns to the next set
# with its wrist rolling into the turn. FanClose curls it shut at the end.
const SPOKE_DIP := 1.4                      # how far the hand bobs down as a set ignites
const SPOKE_ROLL := 0.08                    # radians of wrist roll for each radian a second the hand turns
const SPOKE_MAX_ROLL := 0.45
const SPOKE_FLASH := Color(1.0, 0.95, 0.8)
const SPOKE_GLOW_LOW := 0.45
const SPOKE_GLOW_HIGH := 1.1


func _attack_spokes() -> void:
	anim.get_animation("FanWave").loop_mode = Animation.LOOP_LINEAR
	pose("Clench", 0.15)
	anim.queue("FistTremble")
	set_glow(DANGER_GLOW, SPOKE_GLOW_LOW, 0.6)
	var center := home + flat(target_floor() - home).limit_length(arena_radius * 0.12)
	center.y = floor_y
	var radius := arena_radius + flat_distance(center, home)
	var k := 1.0 / speed()
	var warn := spoke_warn * k
	var beat := spoke_beat * k
	var half := deg_to_rad(spoke_half_angle)
	var height := floor_y + spoke_height
	var angle_of_player := _spoke_angle(center, target_floor())
	var hand_angle := [angle_of_player]
	if not await glide(_spoke_transform(center, angle_of_player, height + 4.0), 0.9 / speed()):
		return
	if not await glide(_spoke_transform(center, angle_of_player, height), 0.4 / speed()):
		return
	# Bloom: the fist snaps open into the fan with a white flash
	pose("FanBloom", 0.05)
	set_glow(SPOKE_FLASH, SPOKE_GLOW_HIGH, 0.05)
	play_sfx(SFX_ROAR)
	if not await wait(0.3):
		return
	set_glow(DANGER_GLOW, SPOKE_GLOW_LOW, 0.4)
	pose("FanWave", 0.2)
	var sets: Array[Dictionary] = []
	for i in spoke_beats:
		sets.append({"time": warn + beat * float(i), "state": 0, "aimed": i % 2 == 0, "angles": [], "teles": []})
	var last_offset := [angle_of_player]
	var roll := [0.0]
	var total: float = sets[sets.size() - 1].time + 0.8
	var ok := await track(total, func(t: float, dt: float):
		var dip := 0.0
		for set_data in sets:
			var strike: float = set_data.time
			if set_data.state == 0 and t >= strike - warn:
				set_data.state = 1
				pose("FanWave", 0.15)
				glow_color = DANGER_GLOW
				skin.set_shader_parameter("glow_color", DANGER_GLOW)
				var offset: float = _spoke_angle(center, target_floor()) if set_data.aimed else last_offset[0] + deg_to_rad(randf_range(30.0, 60.0))
				last_offset[0] = offset
				for quarter in 4:
					var angle := offset + float(quarter) * PI * 0.5
					set_data.angles.append(angle)
					set_data.teles.append(BossTelegraph.sector(get_tree(), center, Vector3(sin(angle), 0.0, cos(angle)), radius, half))
					action_fx.append(set_data.teles[quarter])
			if set_data.state == 1:
				for tele in set_data.teles:
					tele.set_progress(clampf((t - (strike - warn)) / warn, 0.0, 1.0))
				var before: float = hand_angle[0]
				hand_angle[0] = lerp_angle(hand_angle[0], _nearest_spoke(set_data.angles, hand_angle[0]), 1.0 - exp(-4.0 * dt))
				roll[0] = lerpf(roll[0], clampf(angle_difference(before, hand_angle[0]) / dt * SPOKE_ROLL, -SPOKE_MAX_ROLL, SPOKE_MAX_ROLL), 1.0 - exp(-8.0 * dt))
				_apply_glow(lerpf(SPOKE_GLOW_LOW, SPOKE_GLOW_HIGH, clampf((t - (strike - warn)) / warn, 0.0, 1.0)))
				if t >= strike:
					set_data.state = 2
					pose("FanStrike", 0.04)
					for i in 4:
						set_data.teles[i].finish(0.12)
						var angle: float = set_data.angles[i]
						BossBeamSector.spawn(get_tree(), center, Vector3(sin(angle), 0.0, cos(angle)), radius, half, spoke_damage, spoke_burn, spoke_surge_speed)
					WaterRipple.spawn(get_tree(), center, 0.8, 4.0)
					BossDust.spawn(get_tree(), center, 1.0)
					play_sfx(SFX_HIT)
					rattle_player_camera(0.45)
			if set_data.state == 2:
				var since: float = t - strike
				dip = maxf(dip, SPOKE_DIP * sin(clampf(since / 0.3, 0.0, 1.0) * PI))
				# White-hot as the fire goes off, cooling back to red
				var cool := clampf(since / 0.5, 0.0, 1.0)
				if set_data.time >= sets[sets.size() - 1].time or since < 0.4:
					skin.set_shader_parameter("glow_color", SPOKE_FLASH.lerp(DANGER_GLOW, cool))
					_apply_glow(lerpf(1.6, SPOKE_GLOW_LOW, cool))
		roll[0] = lerpf(roll[0], 0.0, 1.0 - exp(-3.0 * dt)) if not _any_charging(sets) else roll[0]
		global_transform = _spoke_transform(center, hand_angle[0], height - dip, roll[0]))
	if not ok:
		return
	pose("FanClose", 0.1)
	glow_off(0.5)
	if not await wait(0.5):
		return
	await glide(hover_transform(), 0.8)


func _any_charging(sets: Array[Dictionary]) -> bool:
	for set_data in sets:
		if set_data.state == 1:
			return true
	return false


# The compass angle (0 along +Z, turning towards +X) of a point as seen from the middle of the spokes
func _spoke_angle(center: Vector3, point: Vector3) -> float:
	var offset := flat(point - center)
	return atan2(offset.x, offset.z) if offset.length() > 0.5 else randf() * TAU


# Of a set's four spoke angles, the one the hand has to turn the least to point along
func _nearest_spoke(angles: Array, from: float) -> float:
	var best: float = angles[0]
	for angle in angles:
		if absf(angle_difference(from, angle)) < absf(angle_difference(from, best)):
			best = angle
	return from + angle_difference(from, best)


# The hand flat, palm down and fingers along `angle`, with the middle of the palm over `center` at wrist height `y`
func _spoke_transform(center: Vector3, angle: float, y: float, roll := 0.0) -> Transform3D:
	var along := Vector3(sin(angle), 0.0, cos(angle))
	var wrist := center - along * hand_length * 0.4
	# `roll` tips the hand about its fingers, like a wrist leaning into a turn
	return Transform3D(hand_basis(along, Vector3.DOWN) * Basis(Vector3.BACK, roll), Vector3(wrist.x, y, wrist.z))


# Rises high, follows the player with its shadow, then presses down flat. Get out from under it, or grapple up.
func _attack_crush() -> void:
	pose("Flat", 0.4)
	play_sfx(SFX_ROAR)
	set_glow(DANGER_GLOW, 0.8, 0.8)
	var along := flat(target_floor() - home)
	along = along.normalized() if along.length() > 1.0 else Vector3.FORWARD
	var basis := hand_basis(along, Vector3.DOWN)
	if not await wait(0.3):
		return
	var low := floor_y + reach_below(basis) - 0.15
	var high := floor_y + 30.0
	var centre_offset := hand_length * 0.4   # the wrist sits this far behind the point it presses on
	var aim := [target_floor()]
	var lane := warn_lane(aim[0] - along * forearm_length, aim[0] + along * hand_length, palm_half_width * 2.2)
	var track_time := crush_track_time / speed()
	var ok := await track(track_time + 0.5, func(t: float, dt: float):
		if t < track_time:
			aim[0] = aim[0].lerp(in_arena(target_floor()), 1.0 - exp(-3.0 * dt))
		var wrist: Vector3 = aim[0] - along * centre_offset
		lane.set_lane(wrist - along * forearm_length * 0.9 + Vector3.UP * BossTelegraph.FLOOR_LIFT,
				wrist + along * hand_length + Vector3.UP * BossTelegraph.FLOOR_LIFT, palm_half_width * 2.2)
		lane.set_progress(t / (track_time + 0.5))
		steer(Transform3D(basis, Vector3(wrist.x, high, wrist.z)), dt, 4.0))
	if not ok:
		return
	var wrist_at: Vector3 = aim[0] - along * centre_offset
	if not await glide(Transform3D(basis, Vector3(wrist_at.x, low, wrist_at.z)), 0.3 / speed(), Ease.IN):
		return
	lane.finish(0.1)
	BossShockwave.spawn(get_tree(), Vector3(aim[0].x, floor_y, aim[0].z), arena_radius * 0.9, 16.0, 0.0, true)
	BossDust.spawn(get_tree(), Vector3(aim[0].x, floor_y, aim[0].z), 1.6)
	play_sfx(SFX_HIT)
	rattle_player_camera(1.0)
	shake_player_camera(0.16, 0.05)
	if player_height() < 4.5 and in_footprint(wrist_at, along, forearm_length * 0.9, hand_length, palm_half_width * 1.1):
		hurt_player(crush_damage, Vector3.UP * 8.0 + flat(target.global_position - wrist_at).normalized() * 10.0)
	set_weak_points(true, false)
	vulnerability = 1.25
	set_glow(WEAK_GLOW, 0.6, 0.2)
	if not await wait(crush_hold / speed()):
		return
	await glide(hover_transform(), 1.2)


# ------------------------------------------------------------------------------------------------------ reactions

# A parried orb hit it: it reels, sinks, and is open to hits for a while
func _stagger() -> void:
	play_sfx(SFX_HIT)
	pose("Stagger", 0.05)
	set_weak_points(false, true)
	vulnerability = open_multiplier
	set_glow(WEAK_GLOW, 0.5, 0.2)
	var sunk := global_transform
	sunk.origin.y = maxf(floor_y + reach_below(global_basis) + 1.0, sunk.origin.y - 4.0)
	if not await glide(sunk, 0.6, Ease.OUT):
		return
	pose("Idle", 0.4, 0.5)
	if not await wait(stagger_time):
		return
	await glide(hover_transform(), 1.0)


# The third poke was parried: the finger is stuck in the floor and the hand strains to pull it out
func _stuck() -> void:
	play_sfx(SFX_HIT)
	shake_player_camera(0.06, 0.02)
	pose("PokeStuck", 0.15)
	set_weak_points(false, true)
	vulnerability = open_multiplier
	set_glow(WEAK_GLOW, 0.5, 0.2)
	var tip := bone_tip("index_3")
	var down := Transform3D(global_basis, global_position + Vector3.DOWN * maxf(tip.y - floor_y - 0.1, 0.0))
	if not await glide(down, 0.1):
		return
	var base := global_transform
	if not await track(stuck_time, func(t: float, _dt: float):
		global_transform = Transform3D(base.basis, base.origin + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.08 * hand_scale * sin(t * 9.0))):
		return
	pose("Release", 0.2)
	ImpactParticles.spawn(get_tree(), Vector3(tip.x, floor_y + 0.2, tip.z), Vector3.UP, 1.5)
	await glide(hover_transform(), 0.7, Ease.OUT)


# Between phases: rises over the middle, clenches, shakes and bursts open
func _transition() -> void:
	invulnerable = true
	play_sfx(SFX_ROAR)
	var basis := hand_basis(Vector3.DOWN, flat(home - target_floor()).normalized() if flat(home - target_floor()).length() > 0.5 else Vector3.FORWARD)
	if not await glide(Transform3D(basis, home + Vector3.UP * (hand_length + hover_clearance + 3.0)), 0.8):
		invulnerable = false
		return
	pose("PhaseRoar", 0.1)
	set_glow(DANGER_GLOW, 1.0, 0.8)
	if not await wait(1.25):
		invulnerable = false
		return
	BossShockwave.spawn(get_tree(), home, arena_radius * 0.85, 18.0, 0.0, true)
	shake_player_camera(0.12, 0.04)
	rattle_player_camera(0.8)
	play_sfx(SFX_ROAR)
	await wait(0.5)
	invulnerable = false


# ------------------------------------------------------------------------------------------------- damage, death

func damage(amount: float, multiplier: float = 1.0) -> void:
	if destroyed or invulnerable:
		return
	_lose_health(amount * multiplier * vulnerability)
	_report_hit(multiplier > 1.0, false)


func _lose_health(amount: float) -> void:
	if destroyed:
		return
	health = maxf(health - amount, 0.0)
	if health_bar:
		health_bar.set_health(health)
	if health <= 0.0:
		_die()
		return
	var ratio := health / max_health
	var next := phase
	if phase == 1 and ratio <= phase_two_at:
		next = 2
	elif phase == 2 and ratio <= phase_three_at:
		next = 3
	if next != phase:
		phase = next
		pending_reaction = ""
		interrupt("transition")


func flinch(world_point: Vector3, strength := 1.0) -> void:
	super(world_point, strength * 0.25)


func _die() -> void:
	if destroyed:
		return
	destroyed = true
	invulnerable = true
	action_token += 1
	_end_action()
	_set_layers_enabled(false)
	change_state("Dead")
	GlobalVariables.enemy_died.emit(self)
	if health_bar:
		health_bar.hide_bar()
	play_sfx(SFX_DEATH)
	_death()


# Spasms, goes limp, and is pulled back up into the portal, which closes behind it. Then the exit portal opens.
func _death() -> void:
	pose("Death", 0.1)
	set_glow(Color(1.0, 1.0, 1.0), 1.2, 0.4)
	var base := global_transform
	var tree := get_tree()
	var timer := 0.0
	while timer < 2.0:
		await tree.physics_frame
		if not is_inside_tree():
			return
		if not can_process():
			continue
		timer += get_physics_process_delta_time()
		global_transform = Transform3D(base.basis, base.origin + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.06 * hand_scale)
		if randf() < 0.08:
			var finger: String = FINGERS.pick_random()
			BLOOD_PARTICLES.spawn_burst(tree, bone_tip("%s_3" % finger), 1.2, blood_scale)
	# The portal stays where it is and the hand is drawn back through it along the forearm
	portal_follows = false
	var out := (bone_head("forearm") - bone_head("hand")).normalized()
	var from := global_transform
	var pull := hand_length + forearm_length + 2.0
	timer = 0.0
	while timer < 2.6:
		await tree.physics_frame
		if not is_inside_tree():
			return
		if not can_process():
			continue
		timer += get_physics_process_delta_time()
		var k := _ease(minf(timer / 2.6, 1.0), Ease.IN)
		global_transform = Transform3D(from.basis, from.origin + out * pull * k)
	model_root.visible = false
	await set_portal_open(0.0, 0.9).finished   # the tear seals itself
	portal.visible = false
	await tree.create_timer(1.0, false).timeout
	# The way out opens in the middle of the arena. Walking in ends the game (no next level to go to).
	var player = GlobalVariables.player
	LevelPortal.open_at(tree, Vector3(home.x, floor_y, home.z), "", player.global_position if is_instance_valid(player) else Vector3.INF)
