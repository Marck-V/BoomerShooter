extends Area3D

const BloodParticles = preload("res://scripts/weapons/blood_particles.gd")
const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")
const ParryFx = preload("res://scripts/enemies/parry_fx.gd")
const GlowTrail = preload("res://scripts/enemies/glow_trail.gd")
const AURA_SHADER: Shader = preload("res://shaders/enemies/parry_aura.gdshader")
const CORE_SHADER: Shader = preload("res://shaders/enemies/energy_ball_core.gdshader")

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D
@onready var audio_player: Node3D = $AudioPlayer

@export var SPEED : float = 10.0
@export var damage : float = 10
@export var turn_rate : float = 2.0  # radians per second
@export var target_offset = Vector3(0.0, 1.0, 0.0)

@export var max_scale: float = 2.0
@export var scale_speed: float = 1.0

var scale_progress: float = 0.0
var target: Node3D
var shooter: Node3D  # enemy that fired this ball, so a parry can send it back to them
var always_return_to_shooter := false  # a parried ball goes back to the shooter however far away it is (the boss's orbs)
var velocity: Vector3
var shell_color := Color(1.0, 0.72, 0.1)  # outer glow. Set before the ball enters the tree.


const REFLECT_SPEED_MULT := 3.2   # a parried ball flies back twice as fast as it came (it used to be 1.6x)
const REFLECT_DAMAGE_MULT := 2.0
const REFLECT_MASK := 2 | 4          # environment + enemy bodies
const REFLECT_HIT_STRENGTH := 3.0     # flinch strength on the enemy a reflected ball lands on
const REFLECT_HIT_FLASH_RADIUS := 1.9 # hit flash radius multiplier
# A boss's orb sent back (always_return_to_shooter) chases its shooter straight on and can't miss: it flies through
# the level, and counts as a hit once it is this close to the point it aims at (on top of one frame's travel)
const RETURN_SPEED_MULT := 4.0
const RETURN_HIT_RADIUS := 1.5

# Yellow always means "you can parry this"; a ball the player sent back turns cyan, like the shield
const SHARD_COLOR := Color(1.4, 1.1, 0.1)
const INCOMING_COLOR := Color(1.0, 0.75, 0.0)
const INCOMING_TAIL_COLOR := Color(1.0, 0.42, 0.0)
const REFLECT_SHARD_COLOR := Color(0.5, 1.5, 2.0)
const REFLECT_COLOR := Color(0.1, 0.75, 1.0)
const REFLECT_TAIL_COLOR := Color(0.1, 0.35, 1.0)

const TRAIL_POINTS := 8
const REFLECT_TRAIL_POINTS := 14
const TRAIL_SPACING := 0.25
const TRAIL_WIDTH := 0.1              # at the head, at scale 1

const CORE_SCALE := 0.32              # the scene's core mesh
const INNER_SHELL_RADIUS := 0.23
const OUTER_SHELL_RADIUS := 0.31      # close to the 0.25 collision radius, so what you see is what can hit you
const SHARD_COUNT := 3
const SHARD_ORBIT := 0.29
const SHARD_SPIN := 7.0               # radians per second
const LIGHT_RANGE := 4.0
const LIGHT_ENERGY := 1.2
const STRETCH_PER_SPEED := 0.012      # how much longer the ball gets along its path per m/s
const MAX_STRETCH := 1.5

# Once the ball is close enough to parry it burns brighter and pulses faster
const PULSE_SPEED := 8.0
const PARRY_PULSE_SPEED := 26.0
const PARRY_CUE_RATE := 12.0
const BASE_GLOW := 1.8
const PARRY_CUE_GLOW := 4.0
const PARRY_CUE_LIGHT := 2.5
const FALLBACK_PARRY_RANGE := 4.0

const GLINT_SIZE := 0.9

const FLASH_LIFE := 0.14
const MUZZLE_FLASH_SIZE := 0.45
const IMPACT_FLASH_SIZE := 0.8

var reflected := false
var trail: Node3D
var glinted := false

var visuals: Node3D
var spinner: Node3D
var core_material: ShaderMaterial
var inner_shell: ShaderMaterial
var outer_shell: ShaderMaterial
var shard_material: StandardMaterial3D
var light: OmniLight3D
var embers: GPUParticles3D
var parry_cue := 0.0
var pulse_phase := 0.0


func _ready():
	velocity = global_transform.basis.z * SPEED
	add_to_group("EnemyProjectile")
	_build_visuals()
	_start_trail()
	# Deferred because whoever spawned the ball only moves it to the muzzle after adding it
	_spawn_muzzle_flash.call_deferred()


# Hot core, two yellow rims around it, shards circling them, a small light and a few sparks. Everything lives under
# one node so it can stretch along the ball's path.
func _build_visuals() -> void:
	visuals = Node3D.new()
	add_child(visuals)
	mesh_instance_3d.reparent(visuals, false)
	core_material = ShaderMaterial.new()
	core_material.shader = CORE_SHADER
	mesh_instance_3d.set_surface_override_material(0, core_material)

	inner_shell = _add_shell(INNER_SHELL_RADIUS, INCOMING_COLOR, 1.0, 0.0)
	outer_shell = _add_shell(OUTER_SHELL_RADIUS, shell_color, 2.0, 2.0)

	shard_material = _make_glow_material(SHARD_COLOR)
	var shard_mesh := SphereMesh.new()
	shard_mesh.radial_segments = 4
	shard_mesh.rings = 1
	shard_mesh.radius = 0.05
	shard_mesh.height = 0.18
	shard_mesh.material = shard_material
	spinner = Node3D.new()
	spinner.rotation = Vector3(randf_range(0.3, 0.9), randf() * TAU, 0.0)
	visuals.add_child(spinner)
	for i in SHARD_COUNT:
		var angle := TAU * i / SHARD_COUNT
		var shard := MeshInstance3D.new()
		shard.mesh = shard_mesh
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.position = Vector3(cos(angle), 0.0, sin(angle)) * SHARD_ORBIT
		spinner.add_child(shard)

	light = OmniLight3D.new()
	light.light_color = INCOMING_COLOR
	light.omni_range = LIGHT_RANGE
	light.light_energy = LIGHT_ENERGY
	add_child(light)

	embers = ParryFx.make_embers(OUTER_SHELL_RADIUS)
	add_child(embers)


func _add_shell(radius: float, color: Color, rim_power: float, phase: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = AURA_SHADER
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("rim_power", rim_power)
	material.set_shader_parameter("phase", phase)
	var mesh := SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = material
	var shell := MeshInstance3D.new()
	shell.mesh = mesh
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visuals.add_child(shell)
	return material


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _spawn_muzzle_flash() -> void:
	_spawn_flash(get_parent(), global_position, INCOMING_COLOR, MUZZLE_FLASH_SIZE)


# A ball of light that swells and fades out. Lives on its own, so it outlasts the projectile that made it.
static func _spawn_flash(parent: Node, point: Vector3, color: Color, size: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, 1.0)
	var mesh := SphereMesh.new()
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.material = material
	var flash := MeshInstance3D.new()
	flash.mesh = mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flash)
	flash.global_position = point
	flash.scale = Vector3.ONE * size * 0.4
	var tween := flash.create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * size, FLASH_LIFE)
	tween.tween_property(material, "albedo_color:a", 0.0, FLASH_LIFE)
	tween.chain().tween_callback(flash.queue_free)


# Sends the ball back: it now ignores the player, homes on new_target and hurts enemies
func reflect(new_target: Node3D, direction: Vector3) -> void:
	if reflected:
		return
	reflected = true
	var returning := always_return_to_shooter and new_target == shooter and is_instance_valid(new_target)
	collision_mask = 4 if returning else REFLECT_MASK   # enemy bodies only: the walls can't stop it on the way
	SPEED *= RETURN_SPEED_MULT if returning else REFLECT_SPEED_MULT
	damage *= REFLECT_DAMAGE_MULT
	velocity = direction.normalized() * SPEED
	target = new_target
	$SelfQueueTimer.start()

	core_material.set_shader_parameter("edge_color", REFLECT_COLOR)
	core_material.set_shader_parameter("center_color", Color.WHITE)
	shard_material.albedo_color = REFLECT_SHARD_COLOR
	inner_shell.set_shader_parameter("aura_color", REFLECT_COLOR)
	outer_shell.set_shader_parameter("aura_color", REFLECT_COLOR)
	light.light_color = REFLECT_COLOR
	embers.emitting = false
	trail.head_color = REFLECT_COLOR
	trail.tail_color = REFLECT_TAIL_COLOR
	trail.max_points = REFLECT_TRAIL_POINTS
	_spawn_flash(get_parent(), global_position, REFLECT_COLOR, IMPACT_FLASH_SIZE)


func _start_trail() -> void:
	trail = GlowTrail.new()
	trail.source = self
	trail.head_color = INCOMING_COLOR
	trail.tail_color = INCOMING_TAIL_COLOR
	trail.max_points = TRAIL_POINTS
	trail.spacing = TRAIL_SPACING
	trail.width = TRAIL_WIDTH
	add_child(trail)


func _process(delta: float) -> void:
	_animate_visuals(delta)


func _animate_visuals(delta: float) -> void:
	spinner.rotate_object_local(Vector3.UP, SHARD_SPIN * delta)
	var stretch := minf(1.0 + velocity.length() * STRETCH_PER_SPEED, MAX_STRETCH)
	var squeeze := 1.0 / sqrt(stretch)
	visuals.scale = Vector3(squeeze, squeeze, stretch)

	var can_be_parried := _can_be_parried()
	if can_be_parried and not glinted:
		glinted = true
		ParryFx.play_star_glint(self, GLINT_SIZE)
	parry_cue = move_toward(parry_cue, 1.0 if can_be_parried else 0.0, PARRY_CUE_RATE * delta)
	pulse_phase += lerpf(PULSE_SPEED, PARRY_PULSE_SPEED, parry_cue) * delta
	var pulse := 0.5 + 0.5 * sin(pulse_phase)
	var glow := lerpf(BASE_GLOW, PARRY_CUE_GLOW, parry_cue) * lerpf(0.8, 1.15, pulse)
	inner_shell.set_shader_parameter("intensity", glow)
	outer_shell.set_shader_parameter("intensity", glow)
	mesh_instance_3d.scale = Vector3.ONE * CORE_SCALE * lerpf(0.92, 1.08, pulse)
	light.light_energy = LIGHT_ENERGY * lerpf(1.0, PARRY_CUE_LIGHT, parry_cue) * lerpf(0.8, 1.1, pulse)


# Same test the shield uses (offhand_shield.gd _check_parry), so the cue is true whenever it shows
func _can_be_parried() -> bool:
	if reflected:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var parry_range := FALLBACK_PARRY_RANGE
	var player = GlobalVariables.player
	if player and is_instance_valid(player):
		var shield = player.get("offhand_shield")
		if shield:
			parry_range = shield.parry_range
	var to_ball := global_position - camera.global_position
	return to_ball.length() <= parry_range and to_ball.dot(-camera.global_basis.z) >= 0.0


func _physics_process(delta):
	# ----- Projectile Scaling -----
	if scale_progress < 1.0:
		scale_progress = min(scale_progress + scale_speed * delta, 1.0)
		var scale_value = lerp(1.0, max_scale, scale_progress)
		scale = Vector3.ONE * scale_value

	if reflected and always_return_to_shooter and target == shooter and is_instance_valid(target):
		# Straight at it every frame, wherever it moves
		var to_aim := _aim_point() - global_position
		if to_aim.length() <= SPEED * delta + RETURN_HIT_RADIUS:
			global_position += to_aim
			_hit_reflected(target)
			return
		velocity = to_aim.normalized() * SPEED
	elif is_instance_valid(target):
		# Homing calculation
		var to_target = (_aim_point() - global_position).normalized()
		var turn_strength = clamp(turn_rate * delta / velocity.length(), 0, 1)
		velocity = velocity.slerp(to_target * SPEED, turn_strength)

	# Move projectile
	global_position += velocity * delta

	# Face direction of travel
	var direction := velocity.normalized()
	if velocity.length() > 0.01 and absf(direction.y) < 0.999:
		look_at(global_position + direction, Vector3.UP)


# Where it homes to on its target: the target's own choice (the hand boss aims it at its palm), else above its origin
func _aim_point() -> Vector3:
	if reflected and target.has_method("reflect_aim_point"):
		return target.reflect_aim_point()
	return target.global_position + target_offset


func set_target(t: Node3D) -> void:
	target = t


func _on_body_entered(body):
	if reflected:
		_hit_reflected(body)
		return

	if body.is_in_group("Player") and body.get("shield_blocking") == true and _is_in_front_of(body):
		body.offhand_shield.on_block_hit(global_position)
		queue_free()
		return

	if not body.is_in_group("Player"):
		_spawn_impact()
	elif body.has_method("damage"):
		# The shared player: this ball's own one is freed along with it before the sound could start
		Audio.play("assets/audio/sfx/enemies/Enemy_ProjectileHit1.wav,
				   assets/audio/sfx/enemies/Enemy_ProjectileHit2.wav")
		# Whoever fired it, or else back along the way it came
		var from = shooter if is_instance_valid(shooter) else global_position - velocity.normalized() * 10.0
		body.damage(damage, false, from)
	queue_free()


# The player already gets the damage flash or the shield's block sparks, right in front of the camera, so this is
# only for hits on anything else
func _spawn_impact() -> void:
	_spawn_flash(get_parent(), global_position, REFLECT_COLOR if reflected else INCOMING_COLOR, IMPACT_FLASH_SIZE * scale.x)
	ImpactParticles.spawn(get_tree(), global_position, -velocity.normalized(), 0.8)


# A ball the player sent back lands on something: an enemy, the level, or the boss that fired it
func _hit_reflected(body: Node) -> void:
	if is_queued_for_deletion():
		return   # already landed this frame
	_spawn_impact()
	# The boss has its own response to a returned orb (it breaks the shield and staggers it)
	if body.has_method("on_reflected_orb_hit"):
		body.on_reflected_orb_hit(damage)
		if body.has_method("hit_flash"):
			body.hit_flash(global_position, REFLECT_HIT_STRENGTH, REFLECT_HIT_FLASH_RADIUS)
		BloodParticles.spawn(get_tree(), global_position, velocity, 2.0, BloodParticles.thickness_for(body))
	elif body.is_in_group("Enemy") and body.has_method("damage"):
		var shielded: bool = "shield" in body and body.shield != null and is_instance_valid(body.shield)
		body.damage(damage)
		if body.has_method("hit_flash"):
			body.hit_flash(global_position, REFLECT_HIT_STRENGTH, REFLECT_HIT_FLASH_RADIUS)
		if not shielded:
			BloodParticles.spawn(get_tree(), global_position, velocity, 1.3, BloodParticles.thickness_for(body))
	queue_free()


# Only shots coming from the front hit the shield; one from behind still hurts
func _is_in_front_of(player: Node3D) -> bool:
	var camera := player.get_viewport().get_camera_3d()
	if camera == null:
		return false
	return (global_position - camera.global_position).dot(-camera.global_basis.z) > 0.0


func _on_self_queue_timer_timeout():
	_spawn_flash(get_parent(), global_position, REFLECT_COLOR if reflected else INCOMING_COLOR, MUZZLE_FLASH_SIZE * scale.x)
	queue_free()
