extends Node3D

# Shield shatter: a bright white pop, a spray of sparks, and metal shards that fly off and fall.
# Built in code so there is no scene to maintain.
# Use: ShieldBreakEffect.spawn(get_tree(), world_position)

const BREAK_SOUND := "assets/sounds/glass_breaking.mp3"
const SPARK_COUNT := 28
const SHARD_COUNT := 22
const CLEANUP_TIME := 1.8
const POP_TIME := 0.22

static var _spark_mesh: TubeTrailMesh
static var _shard_mesh: BoxMesh
static var _glow_texture: GradientTexture2D

var _pop: MeshInstance3D
var _pop_material: StandardMaterial3D
var _light: OmniLight3D


static func spawn(tree: SceneTree, point: Vector3) -> void:
	var effect: Node3D = new()
	tree.root.add_child(effect)
	effect.global_position = point
	effect._start()


func _start() -> void:
	Audio.play(BREAK_SOUND)
	_add_pop()
	_add_sparks()
	_add_shards()
	get_tree().create_timer(CLEANUP_TIME).timeout.connect(queue_free)


func _add_pop() -> void:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(0.85, 0.9, 1.0, 0.8),
			Color(0.6, 0.7, 1.0, 0.0),
		])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 128
		_glow_texture.height = 128

	_pop_material = StandardMaterial3D.new()
	_pop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pop_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pop_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_pop_material.billboard_keep_scale = true
	_pop_material.albedo_texture = _glow_texture
	_pop_material.albedo_color = Color(4.0, 4.0, 4.0)

	_pop = MeshInstance3D.new()
	_pop.mesh = QuadMesh.new()
	_pop.material_override = _pop_material
	_pop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop.scale = Vector3.ONE * 0.5
	add_child(_pop)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.9, 0.95, 1.0)
	_light.light_energy = 12.0
	_light.omni_range = 5.0
	add_child(_light)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(_pop, "scale", Vector3.ONE * 2.4, POP_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(_pop_material, "albedo_color", Color(0.0, 0.0, 0.0), POP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_light, "light_energy", 0.0, POP_TIME * 1.5)


func _add_sparks() -> void:
	if _spark_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.vertex_color_use_as_albedo = true
		material.use_particle_trails = true
		material.albedo_color = Color(3.0, 3.0, 3.0)

		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 1.0))
		taper.add_point(Vector2(1.0, 0.0))

		_spark_mesh = TubeTrailMesh.new()
		_spark_mesh.radius = 0.014
		_spark_mesh.radial_steps = 4
		_spark_mesh.sections = 6
		_spark_mesh.section_length = 0.18
		_spark_mesh.section_rings = 2
		_spark_mesh.curve = taper
		_spark_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.85, 0.5, 0.9),
		Color(1.0, 0.5, 0.2, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 10.0
	process.gravity = Vector3(0.0, -10.0, 0.0)
	process.damping_min = 0.5
	process.damping_max = 1.5
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color_ramp = ramp

	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = SPARK_COUNT
	sparks.lifetime = 0.6
	sparks.fixed_fps = 60
	sparks.trail_enabled = true
	sparks.trail_lifetime = 0.14
	sparks.process_material = process
	sparks.draw_pass_1 = _spark_mesh
	sparks.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	add_child(sparks)
	sparks.emitting = true


func _add_shards() -> void:
	if _shard_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(1.6, 1.6, 1.8)
		_shard_mesh = BoxMesh.new()
		_shard_mesh.size = Vector3(0.11, 0.02, 0.07)
		_shard_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.75, 0.65, 0.9, 1.0),
		Color(0.55, 0.3, 0.7, 0.0),
	])

	var shards := CPUParticles3D.new()
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.randomness = 0.4
	shards.amount = SHARD_COUNT
	shards.lifetime = 1.3
	shards.mesh = _shard_mesh
	shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	shards.emission_sphere_radius = 0.4
	shards.direction = Vector3.UP
	shards.spread = 140.0
	shards.initial_velocity_min = 2.0
	shards.initial_velocity_max = 5.5
	shards.gravity = Vector3(0.0, -13.0, 0.0)
	shards.angular_velocity_min = -540.0
	shards.angular_velocity_max = 540.0
	shards.angle_min = 0.0
	shards.angle_max = 360.0
	shards.scale_amount_min = 0.6
	shards.scale_amount_max = 1.6
	shards.color_ramp = fade
	add_child(shards)
	shards.emitting = true
