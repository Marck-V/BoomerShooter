extends Area3D

@export var heal_amount := 5
@export var lifespan := 3.0
@export var rise_speed := 2.0
@export var fade_time := 0.5

var age := 0.0
var collected := false


static var _drip_mesh: TubeTrailMesh


func _ready() -> void:
	add_to_group("LifestealOrb")
	_add_drips()


# Droplets fall off the orb and are left behind in the world as it rises, trailing short red streaks
func _add_drips() -> void:
	if _drip_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.use_particle_trails = true
		material.albedo_color = Color(1.6, 1.0, 1.0)

		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 1.0))
		taper.add_point(Vector2(1.0, 0.0))

		_drip_mesh = TubeTrailMesh.new()
		_drip_mesh.radius = 0.04
		_drip_mesh.radial_steps = 4
		_drip_mesh.sections = 6
		_drip_mesh.section_length = 0.16
		_drip_mesh.section_rings = 2
		_drip_mesh.curve = taper
		_drip_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([
		Color(0.95, 0.05, 0.08, 1.0),
		Color(0.7, 0.02, 0.05, 1.0),
		Color(0.45, 0.0, 0.03, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.14
	process.direction = Vector3.DOWN
	process.spread = 35.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color_ramp = ramp

	var drips := GPUParticles3D.new()
	drips.amount = 18
	drips.lifetime = 0.7
	drips.explosiveness = 0.0
	drips.randomness = 0.6
	drips.fixed_fps = 60
	drips.local_coords = false
	drips.trail_enabled = true
	drips.trail_lifetime = 0.18
	drips.process_material = process
	drips.draw_pass_1 = _drip_mesh
	drips.visibility_aabb = AABB(Vector3(-2, -4, -2), Vector3(4, 5, 4))
	add_child(drips)
	drips.emitting = true


func _process(delta: float) -> void:
	age += delta
	global_position.y += rise_speed * delta

	var remaining := lifespan - age
	if remaining <= 0.0:
		queue_free()
	elif remaining <= fade_time:
		scale = Vector3.ONE * (remaining / fade_time)


func damage(_amount = 0, _multiplier = 1.0) -> void:
	if collected:
		return
	collected = true
	GlobalVariables.add_health(heal_amount)
	queue_free()
