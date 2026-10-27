extends Node3D
class_name BossDust

# A burst of dust clouds thrown out around a big landing: a ring of soft puffs rolling outwards along the floor,
# a taller plume rising from the middle and a few chunks kicked up. Soft alpha-blended puffs (not additive), tinted
# towards the level's purple haze so they sit in the scene. Built in code, cleans itself up.
#   BossDust.spawn(tree, floor_position, size)        size is the boss's scale: 4 for the real boss

const LIFETIME := 3.2

static var _puff_texture: GradientTexture2D


static func spawn(tree: SceneTree, floor_position: Vector3, size := 1.0) -> BossDust:
	var dust := BossDust.new()
	tree.current_scene.add_child(dust)
	dust.global_position = floor_position
	dust._start(size)
	return dust


func _start(size: float) -> void:
	# Low ring rolling out along the floor
	_add_puffs(70, 1.9, size * 0.9, Vector2(size * 3.2, size * 5.6), 0.2, 0.06, 1.0)
	# A second, slower ring of bigger puffs for body
	_add_puffs(34, 2.6, size * 1.5, Vector2(size * 1.6, size * 3.0), 0.35, 0.1, 1.15)
	# Plume rising from the middle
	_add_plume(26, 2.2, size)
	# A few darker chunks of floor kicked up
	_add_chunks(18, size)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


# Ring emission with an outward velocity: soft puffs that grow while they fade
func _add_puffs(count: int, life: float, puff_size: float, speed: Vector2, rise: float, damping: float, opacity: float) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = puff_size * 0.9
	process.emission_ring_inner_radius = puff_size * 0.2
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.6
	process.radial_velocity_min = speed.x
	process.radial_velocity_max = speed.y
	process.gravity = Vector3(0.0, rise, 0.0)
	process.damping_min = 1.6 + damping * 20.0
	process.damping_max = 2.6 + damping * 20.0
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.35, 1.0), Vector2(1.0, 1.7)])
	process.color_ramp = _ramp(opacity)
	process.angle_min = -180.0
	process.angle_max = 180.0
	add_child(_make_particles(process, count, life, puff_size * 1.5, 0.0))


func _add_plume(count: int, life: float, size: float) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size * 0.7
	process.direction = Vector3.UP
	process.spread = 28.0
	process.initial_velocity_min = size * 1.2
	process.initial_velocity_max = size * 2.6
	process.gravity = Vector3(0.0, 0.5, 0.0)
	process.damping_min = 0.9
	process.damping_max = 1.6
	process.scale_min = 0.8
	process.scale_max = 1.4
	process.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.5, 1.1), Vector2(1.0, 1.9)])
	process.color_ramp = _ramp(0.9)
	process.angle_min = -180.0
	process.angle_max = 180.0
	add_child(_make_particles(process, count, life, size * 1.4, 0.05))


# Small dark chunks that fly up and fall back
func _add_chunks(count: int, size: float) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = size * 1.2
	process.emission_ring_inner_radius = size * 0.3
	process.emission_ring_height = 0.1
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = size * 2.0
	process.initial_velocity_max = size * 5.0
	process.gravity = Vector3(0.0, -18.0, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.3
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(0.22, 0.12, 0.3, 1.0), Color(0.18, 0.1, 0.26, 1.0), Color(0.15, 0.08, 0.22, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	var quad := BoxMesh.new()
	quad.size = Vector3.ONE * size * 0.12
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = 1.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 40, 80))
	particles.emitting = true
	add_child(particles)


func _make_particles(process: ParticleProcessMaterial, count: int, life: float, puff_size: float, delay: float) -> GPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _puff()
	material.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(puff_size, puff_size)
	quad.material = material

	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = life
	particles.one_shot = true
	particles.explosiveness = 0.92 if delay <= 0.0 else 0.8
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 40, 80))
	particles.emitting = true
	return particles


# Soft round puff
static func _puff() -> GradientTexture2D:
	if _puff_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_puff_texture = GradientTexture2D.new()
		_puff_texture.gradient = gradient
		_puff_texture.fill = GradientTexture2D.FILL_RADIAL
		_puff_texture.fill_from = Vector2(0.5, 0.5)
		_puff_texture.fill_to = Vector2(1.0, 0.5)
		_puff_texture.width = 96
		_puff_texture.height = 96
	return _puff_texture


# Dust colour over a puff's life: lit lavender-grey at first, darker and clearer as it spreads
static func _ramp(opacity: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.78, 0.62, 0.9, 0.0),
		Color(0.7, 0.55, 0.85, 0.75 * opacity),
		Color(0.4, 0.28, 0.55, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


static func _curve(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for point in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
