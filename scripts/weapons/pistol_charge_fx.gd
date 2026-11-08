extends Node3D
class_name PistolChargeFx

# The energy stored in the pistol's barrel while a Parry Round is ready (see pistol.gd): a white core flickering and
# straining inside the muzzle, tiny sparks lashing about at the opening as if trying to get out, and a small light that
# stutters with it. Built in code and placed at the muzzle (a child of the pistol's MuzzleLocation, a little way back
# inside the barrel). pistol.gd calls set_strength() every frame: 0 hides it, 1 is full.
# The barrel's own cracks of light are the overlay shader (shaders/player/pistol_charge_glow.gdshader).

const CORE_SIZE := 0.026               # metres across, at its largest
const LIGHT_RANGE := 1.6
const LIGHT_ENERGY := 1.4

static var _glow_texture: GradientTexture2D

var core: MeshInstance3D
var core_material: StandardMaterial3D
var sparks: GPUParticles3D
var light: OmniLight3D
var strength := 0.0
var surge := 0.0


func _ready() -> void:
	core_material = StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	core_material.billboard_keep_scale = true
	core_material.albedo_texture = _glow_tex()
	core_material.albedo_color = Color(2.0, 2.0, 2.0, 1.0)
	core = MeshInstance3D.new()
	core.mesh = QuadMesh.new()
	core.material_override = core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	_build_sparks()

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 1.0, 1.0)
	light.omni_range = LIGHT_RANGE
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	visible = false


# Lashing, jittering sparks right at the opening: fast out, then they stall and whip about in turbulence and die
func _build_sparks() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.use_particle_trails = true
	material.albedo_color = Color(2.5, 2.5, 2.5)
	var mesh := RibbonTrailMesh.new()
	mesh.shape = RibbonTrailMesh.SHAPE_CROSS
	mesh.size = 0.005
	mesh.sections = 3
	mesh.section_length = 0.012
	mesh.section_segments = 1
	mesh.material = material

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.008
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.8
	process.gravity = Vector3.ZERO
	process.damping_min = 6.0
	process.damping_max = 14.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 6.0
	process.turbulence_noise_scale = 2.0
	process.turbulence_noise_speed_random = 1.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	process.color_ramp = ramp

	sparks = GPUParticles3D.new()
	sparks.amount = 28
	sparks.lifetime = 0.22
	sparks.explosiveness = 0.0
	sparks.randomness = 1.0
	sparks.fixed_fps = 60
	sparks.local_coords = true
	sparks.trail_enabled = true
	sparks.trail_lifetime = 0.06
	sparks.process_material = process
	sparks.draw_pass_1 = mesh
	sparks.visibility_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1.0, 1.0, 1.0))
	sparks.emitting = false
	add_child(sparks)


func set_strength(value: float) -> void:
	strength = value
	visible = value > 0.01
	sparks.emitting = value > 0.05


func _process(delta: float) -> void:
	if strength <= 0.01:
		return
	# Chaotic: the core jumps to a random size and brightness every frame, with the odd surge of light
	surge = maxf(surge - delta * 6.0, 0.0)
	if randf() < 0.07:
		surge = 1.0
	var jitter := randf_range(0.45, 1.0) + surge * 0.6
	core.scale = Vector3.ONE * CORE_SIZE * jitter * strength
	var bright := (0.6 + 0.4 * randf()) * strength
	core_material.albedo_color = Color(2.0 * bright, 2.0 * bright, 2.0 * bright, 1.0)
	light.light_energy = LIGHT_ENERGY * bright * (0.6 + surge)
	core.position = Vector3(randf_range(-0.0015, 0.0015), randf_range(-0.0015, 0.0015), 0.0)


static func _glow_tex() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 128
		_glow_texture.height = 128
	return _glow_texture
