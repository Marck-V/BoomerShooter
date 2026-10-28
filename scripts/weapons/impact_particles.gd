extends Node3D

# Sparks + smoke burst spawned where a bullet hits. Built in code so there is no scene to maintain.
# Use: ImpactParticles.spawn(get_tree(), hit_point, hit_normal, amount_scale)

const SPARK_COUNT := 14
const SMOKE_COUNT := 7
const CLEANUP_TIME := 1.6

static var _spark_mesh: RibbonTrailMesh
static var _spark_process: ParticleProcessMaterial
static var _smoke_mesh: QuadMesh
static var _smoke_process: ParticleProcessMaterial


static func spawn(tree: SceneTree, point: Vector3, normal: Vector3, amount_scale := 1.0) -> void:
	var effect: Node3D = new()
	tree.root.add_child(effect)
	effect._start(point, normal, amount_scale)


func _start(point: Vector3, normal: Vector3, amount_scale: float) -> void:
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	global_basis = Basis(x, up, x.cross(up))
	global_position = point + up * 0.03

	_add_sparks(maxi(int(SPARK_COUNT * amount_scale), 3))
	_add_smoke(maxi(int(SMOKE_COUNT * amount_scale), 2))
	get_tree().create_timer(CLEANUP_TIME).timeout.connect(queue_free)


func _add_sparks(count: int) -> void:
	if _spark_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.vertex_color_use_as_albedo = true
		material.use_particle_trails = true
		material.albedo_color = Color(2.5, 1.8, 0.9)
		# The trail follows each spark's path, which is what draws the streak
		_spark_mesh = RibbonTrailMesh.new()
		_spark_mesh.shape = RibbonTrailMesh.SHAPE_CROSS
		_spark_mesh.size = 0.025
		_spark_mesh.sections = 4
		_spark_mesh.section_length = 0.05
		_spark_mesh.section_segments = 1
		_spark_mesh.material = material

		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 0.95, 0.7, 1.0),
			Color(1.0, 0.55, 0.15, 0.9),
			Color(1.0, 0.25, 0.0, 0.0),
		])
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient

		_spark_process = ParticleProcessMaterial.new()
		_spark_process.direction = Vector3.UP
		_spark_process.spread = 60.0
		_spark_process.initial_velocity_min = 2.5
		_spark_process.initial_velocity_max = 6.5
		_spark_process.gravity = Vector3(0.0, -9.8, 0.0)
		_spark_process.damping_min = 1.0
		_spark_process.damping_max = 3.0
		_spark_process.scale_min = 0.6
		_spark_process.scale_max = 1.2
		_spark_process.color_ramp = ramp

	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = count
	sparks.lifetime = 0.4
	sparks.trail_enabled = true
	sparks.trail_lifetime = 0.12
	sparks.process_material = _spark_process
	sparks.draw_pass_1 = _spark_mesh
	add_child(sparks)
	sparks.emitting = true


func _add_smoke(count: int) -> void:
	if _smoke_mesh == null:
		var puff := Gradient.new()
		puff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		puff.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.45),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		var texture := GradientTexture2D.new()
		texture.gradient = puff
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.particles_anim_h_frames = 1
		material.particles_anim_v_frames = 1
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = texture
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(0.3, 0.3)
		_smoke_mesh.material = material

		var fade := Gradient.new()
		fade.offsets = PackedFloat32Array([0.0, 1.0])
		fade.colors = PackedColorArray([
			Color(0.62, 0.62, 0.66, 0.55),
			Color(0.32, 0.32, 0.36, 0.0),
		])
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade

		var growth := Curve.new()
		growth.add_point(Vector2(0.0, 0.35))
		growth.add_point(Vector2(1.0, 1.6))
		var growth_texture := CurveTexture.new()
		growth_texture.curve = growth

		_smoke_process = ParticleProcessMaterial.new()
		_smoke_process.direction = Vector3.UP
		_smoke_process.spread = 35.0
		_smoke_process.initial_velocity_min = 0.4
		_smoke_process.initial_velocity_max = 1.2
		_smoke_process.gravity = Vector3(0.0, 0.7, 0.0)
		_smoke_process.damping_min = 0.6
		_smoke_process.damping_max = 1.2
		_smoke_process.scale_min = 0.7
		_smoke_process.scale_max = 1.1
		_smoke_process.scale_curve = growth_texture
		_smoke_process.color_ramp = ramp

	var smoke := GPUParticles3D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.amount = count
	smoke.lifetime = 0.8
	smoke.process_material = _smoke_process
	smoke.draw_pass_1 = _smoke_mesh
	add_child(smoke)
	smoke.emitting = true
