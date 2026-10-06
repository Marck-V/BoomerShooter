extends Node3D

# Blood spray spawned where a bullet hits an enemy. Built in code so there is no scene to maintain.
# Streaks are GPU particles with trails, so each droplet leaves a tapered ribbon behind it.
# Use: BloodParticles.spawn(get_tree(), hit_point, shot_direction, amount_scale)

const STREAK_COUNT := 16
const BACKSPRAY_COUNT := 5
const MIST_COUNT := 4
const BURST_STREAK_COUNT := 36
const BURST_MIST_COUNT := 8
const CLEANUP_TIME := 1.4

static var _streak_mesh: TubeTrailMesh
static var _mist_mesh: QuadMesh


static func spawn(tree: SceneTree, point: Vector3, direction: Vector3, amount_scale := 1.0) -> void:
	var effect: Node3D = new()
	tree.root.add_child(effect)
	effect._start(point, direction, amount_scale)


# Death burst: streaks and mist thrown out in every direction from the body
static func spawn_burst(tree: SceneTree, point: Vector3, amount_scale := 1.0) -> void:
	var effect: Node3D = new()
	tree.root.add_child(effect)
	effect._start_burst(point, amount_scale)


func _start_burst(point: Vector3, amount_scale: float) -> void:
	global_position = point
	_add_streaks(maxi(int(BURST_STREAK_COUNT * amount_scale), 8), 180.0, 3.0, 8.5, 0.7)
	_add_mist(maxi(int(BURST_MIST_COUNT * amount_scale), 3), 180.0)
	get_tree().create_timer(CLEANUP_TIME).timeout.connect(queue_free)


func _start(point: Vector3, direction: Vector3, amount_scale: float) -> void:
	var dir := direction.normalized()
	global_position = point

	# Main spray carries on in the direction of the shot, arcing slightly upward
	var spray := (dir + Vector3.UP * 0.25).normalized()
	global_basis = _basis_facing(spray)

	_add_streaks(maxi(int(STREAK_COUNT * amount_scale), 4), 38.0, 4.0, 9.0, 0.5)

	# Smaller burst thrown back out of the entry side
	var back := _add_streaks(maxi(int(BACKSPRAY_COUNT * amount_scale), 2), 55.0, 1.5, 4.0, 0.35)
	back.global_basis = _basis_facing((-dir + Vector3.UP * 0.3).normalized())

	_add_mist(maxi(int(MIST_COUNT * amount_scale), 2))
	get_tree().create_timer(CLEANUP_TIME).timeout.connect(queue_free)


func _basis_facing(up: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	return Basis(x, up, x.cross(up))


func _add_streaks(count: int, spread: float, vel_min: float, vel_max: float, life: float) -> GPUParticles3D:
	if _streak_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.use_particle_trails = true
		material.albedo_color = Color(1.6, 1.0, 1.0)

		# Thick at the head of the droplet, tapering to nothing along its trail
		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 1.0))
		taper.add_point(Vector2(1.0, 0.0))

		_streak_mesh = TubeTrailMesh.new()
		_streak_mesh.radius = 0.028
		_streak_mesh.radial_steps = 4
		_streak_mesh.sections = 6
		_streak_mesh.section_length = 0.2
		_streak_mesh.section_rings = 2
		_streak_mesh.curve = taper
		_streak_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray([
		Color(0.9, 0.04, 0.08, 1.0),
		Color(0.65, 0.02, 0.05, 1.0),
		Color(0.4, 0.0, 0.03, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = spread
	process.initial_velocity_min = vel_min
	process.initial_velocity_max = vel_max
	process.gravity = Vector3(0.0, -12.0, 0.0)
	process.damping_min = 0.5
	process.damping_max = 1.5
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color_ramp = ramp

	var streaks := GPUParticles3D.new()
	streaks.one_shot = true
	streaks.explosiveness = 1.0
	streaks.amount = count
	streaks.lifetime = life
	streaks.fixed_fps = 60
	streaks.trail_enabled = true
	streaks.trail_lifetime = 0.16
	streaks.process_material = process
	streaks.draw_pass_1 = _streak_mesh
	streaks.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	add_child(streaks)
	streaks.emitting = true
	return streaks


func _add_mist(count: int, spread := 30.0) -> void:
	if _mist_mesh == null:
		var puff := Gradient.new()
		puff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		puff.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.4),
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
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = texture
		_mist_mesh = QuadMesh.new()
		_mist_mesh.size = Vector2(0.22, 0.22)
		_mist_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([
		Color(0.7, 0.03, 0.06, 0.4),
		Color(0.45, 0.0, 0.03, 0.0),
	])

	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.5))
	growth.add_point(Vector2(1.0, 1.5))

	var mist := CPUParticles3D.new()
	mist.one_shot = true
	mist.explosiveness = 0.9
	mist.amount = count
	mist.lifetime = 0.4
	mist.mesh = _mist_mesh
	mist.direction = Vector3.UP
	mist.spread = spread
	mist.initial_velocity_min = 0.5
	mist.initial_velocity_max = 1.6
	mist.gravity = Vector3.ZERO
	mist.damping_min = 1.0
	mist.damping_max = 2.0
	mist.scale_amount_curve = growth
	mist.color_ramp = fade
	add_child(mist)
	mist.emitting = true
