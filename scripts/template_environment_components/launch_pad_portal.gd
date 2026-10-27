@tool
extends Node3D
class_name LaunchPadPortal

# The look of a launchpad: a purple portal lying on the ground. A swirling vortex disc with a glowing rim, a
# faint column of light rising out of it, sparks drifting upward and a purple glow on the floor around it.
# play_burst() gives the launch some punch (flash, expanding ring, sparks). Everything is built in code and
# nothing is saved into the scene; as a @tool script it also shows up in the editor.

const PORTAL_SHADER: Shader = preload("res://shaders/launch_portal.gdshader")
const BEAM_SHADER: Shader = preload("res://shaders/launch_portal_beam.gdshader")

@export var radius := 0.75
@export var beam_height := 2.4
@export var light_energy := 1.3

const RIM_COLOR := Color(0.7, 0.28, 1.0)
const SPARK_COLOR := Color(0.6, 0.2, 1.0)
const GLOW_BOOST := 1.9           # over 1.0 so the glow effect picks the bright parts up
const SPARK_BOOST := 1.4
const BURST_TIME := 0.4

var disc_material: ShaderMaterial
var shock_ring: MeshInstance3D
var shock_material: StandardMaterial3D
var burst_particles: GPUParticles3D
var light: OmniLight3D
var flash := 0.0
var time := 0.0
var shock_tween: Tween


func _ready() -> void:
	_build_disc()
	_build_rim()
	_build_beam()
	_build_sparks()
	_build_burst()
	_build_light()


func _process(delta: float) -> void:
	time += delta
	flash = move_toward(flash, 0.0, delta * 3.0)
	if disc_material != null:
		disc_material.set_shader_parameter("flash", flash)
	if light != null:
		light.light_energy = light_energy * (1.0 + 0.18 * sin(time * 4.0)) + flash * 3.0


# Called when something is launched: the disc flares, a ring shoots out and sparks fly up
func play_burst() -> void:
	flash = 1.5
	if burst_particles != null:
		burst_particles.restart()
		burst_particles.emitting = true
	if shock_ring == null:
		return
	if shock_tween != null and shock_tween.is_valid():
		shock_tween.kill()
	shock_ring.visible = true
	shock_ring.scale = Vector3.ONE
	shock_material.albedo_color.a = 0.9
	shock_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	shock_tween.tween_property(shock_ring, "scale", Vector3(2.6, 1.0, 2.6), BURST_TIME)
	shock_tween.tween_property(shock_material, "albedo_color:a", 0.0, BURST_TIME)
	shock_tween.chain().tween_callback(func(): shock_ring.visible = false)


func _build_disc() -> void:
	disc_material = ShaderMaterial.new()
	disc_material.shader = PORTAL_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var disc := MeshInstance3D.new()
	disc.mesh = plane
	disc.material_override = disc_material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.01
	add_child(disc)


# A thin glowing ring around the edge, so the portal has a solid frame
func _build_rim() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b) * GLOW_BOOST
	var rim := MeshInstance3D.new()
	rim.mesh = _make_ring(radius, 0.04, material)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.position.y = 0.03
	add_child(rim)


func _build_beam() -> void:
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	material.set_shader_parameter("height", beam_height)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.95
	cylinder.bottom_radius = radius * 0.95
	cylinder.height = beam_height
	cylinder.radial_segments = 24
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = cylinder
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = beam_height * 0.5 + 0.02
	add_child(beam)


func _build_sparks() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius * 0.95
	process.emission_ring_inner_radius = radius * 0.5
	process.emission_ring_height = 0.05
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 1.6
	process.gravity = Vector3.ZERO
	process.damping_min = 0.2
	process.damping_max = 0.6
	process.scale_min = 0.5
	process.scale_max = 1.1
	process.color_ramp = _spark_ramp()
	var sparks := _make_particles(process, 28, 1.7, 0.07)
	sparks.preprocess = 1.5   # already in full flow when the level starts
	add_child(sparks)


func _build_burst() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = radius * 0.9
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.05
	process.direction = Vector3.UP
	process.spread = 40.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, -5.0, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color_ramp = _spark_ramp()
	burst_particles = _make_particles(process, 40, 0.7, 0.09)
	burst_particles.one_shot = true
	burst_particles.explosiveness = 1.0
	burst_particles.emitting = false
	add_child(burst_particles)


func _build_light() -> void:
	light = OmniLight3D.new()
	light.light_color = Color(0.6, 0.2, 1.0)
	light.omni_range = 4.5
	light.light_energy = light_energy
	light.shadow_enabled = false
	light.position.y = 0.5
	add_child(light)
	# The ring that shoots outwards on a launch
	shock_material = StandardMaterial3D.new()
	shock_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shock_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shock_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shock_material.albedo_color = Color(RIM_COLOR.r * GLOW_BOOST, RIM_COLOR.g * GLOW_BOOST, RIM_COLOR.b * GLOW_BOOST, 0.0)
	shock_ring = MeshInstance3D.new()
	shock_ring.mesh = _make_ring(radius, 0.06, shock_material)
	shock_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shock_ring.position.y = 0.04
	shock_ring.visible = false
	add_child(shock_ring)


func _make_ring(ring_radius: float, thickness: float, material: Material) -> TorusMesh:
	var ring := TorusMesh.new()
	ring.inner_radius = ring_radius - thickness
	ring.outer_radius = ring_radius
	ring.rings = 32
	ring.ring_segments = 6
	ring.material = material
	return ring


func _make_particles(process: ParticleProcessMaterial, count: int, lifetime: float, size: float) -> GPUParticles3D:
	var texture := GradientTexture2D.new()
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	texture.gradient = dot
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color(SPARK_BOOST, SPARK_BOOST, SPARK_BOOST, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material

	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-2.5, -1.0, -2.5), Vector3(5.0, 6.0, 5.0))
	particles.position.y = 0.04
	return particles


func _spark_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.9, 0.6, 1.0, 1.0),
		SPARK_COLOR,
		Color(0.35, 0.05, 0.7, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
