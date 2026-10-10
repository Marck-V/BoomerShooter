extends RefCounted

# Neon "teleport in" burst where an enemy appears: a column of light, a burst of blue dust trails and a
# short light flash. Everything cleans itself up. Use: SpawnEffect.play(tree, position)

const LIFETIME := 1.8

static var _trail_meshes := {}


static func play(tree: SceneTree, position: Vector3) -> void:
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = position

	# Blue dust: glowing streaks that fly up and out, slow down and drift, each leaving a tapering trail
	_add_dust(root, 40, 1.0, Vector2(3.0, 6.5), 75.0, 0.04)
	# A finer, slower layer of dust that hangs around the column
	_add_dust(root, 30, 1.3, Vector2(0.8, 2.4), 30.0, 0.024)

	# Light column that fades out
	var column := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.55
	cylinder.bottom_radius = 0.7
	cylinder.height = 6.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.35, 0.95, 0.8)
	material.disable_fog = true
	cylinder.material = material
	column.mesh = cylinder
	column.position.y = 3.0
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(column)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.95)
	light.light_energy = 6.0
	light.omni_range = 6.0
	light.position.y = 1.2
	root.add_child(light)

	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.5)
	tween.tween_property(column, "scale", Vector3(0.2, 1.0, 0.2), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(light, "light_energy", 0.0, 0.45)
	tree.create_timer(LIFETIME).timeout.connect(root.queue_free)


# One-shot GPU particle burst whose particles leave a tapering trail (like the blood streaks, but blue and floaty)
static func _add_dust(root: Node3D, count: int, life: float, speed: Vector2, spread: float, radius: float) -> void:
	var mesh := _trail_mesh(radius)

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	fade.colors = PackedColorArray([
		Color(0.5, 0.82, 1.0, 1.0),
		Color(0.2, 0.5, 1.0, 0.8),
		Color(0.08, 0.2, 0.9, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = spread
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3(0.0, 0.8, 0.0)      # dust drifts up instead of falling
	process.damping_min = 2.5
	process.damping_max = 5.0
	# Swirl so the trails curl like drifting dust instead of flying straight
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.6
	process.turbulence_noise_scale = 2.2
	process.turbulence_influence_min = 0.15
	process.turbulence_influence_max = 0.35
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.35
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.05
	process.color_ramp = ramp

	var dust := GPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = count
	dust.lifetime = life
	dust.fixed_fps = 60
	dust.trail_enabled = true
	dust.trail_lifetime = 0.5
	dust.process_material = process
	dust.draw_pass_1 = mesh
	dust.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 10, 10))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dust)
	dust.emitting = true


static func _trail_mesh(radius: float) -> TubeTrailMesh:
	if _trail_meshes.has(radius):
		return _trail_meshes[radius]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.use_particle_trails = true
	material.albedo_color = Color(0.9, 1.1, 1.7)
	material.disable_fog = true

	# Thick at the head of each particle, tapering to nothing along its trail
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.0))

	var mesh := TubeTrailMesh.new()
	mesh.radius = radius
	mesh.radial_steps = 4
	mesh.sections = 7
	mesh.section_length = 0.2
	mesh.section_rings = 2
	mesh.curve = taper
	mesh.material = material
	_trail_meshes[radius] = mesh
	return mesh
