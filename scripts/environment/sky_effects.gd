extends Node3D

# Far-away sky scenery that behaves like part of the skybox (it follows the camera, so it never
# gets closer): shooting stars, neon light pillars and big wireframe landmarks on the horizon.
# Everything moves in stepped, low-framerate motion to match the rest of the game.

const NeonMesh = preload("res://scripts/environment/neon_mesh.gd")

var ground_height := -90.0
var sun_direction := Vector3(-0.3, 0.12, -1.0)
var random_seed := 7
var enable_shooting_stars := true
var enable_landmarks := true
var enable_beams := true

const STEP_FPS := 12.0
const STAR_DISTANCE := 900.0
const STAR_LENGTH := 120.0
const STAR_LIFETIME := 0.8
const STAR_SPEED := 650.0
const STAR_GAP := Vector2(2.5, 6.0)

var rng := RandomNumberGenerator.new()
var camera: Camera3D
var star: MeshInstance3D
var star_material: StandardMaterial3D
var star_time := -1.0              # negative while waiting for the next one
var star_wait := 1.0
var star_origin := Vector3.ZERO
var star_direction := Vector3.RIGHT
var beams: Array[MeshInstance3D] = []
var beam_material: StandardMaterial3D
var spinner: MeshInstance3D
var step_clock := 0.0
var sun_azimuth := 0.0


func _ready() -> void:
	top_level = true
	rng.seed = random_seed + 11
	var sun := sun_direction.normalized()
	sun_azimuth = atan2(sun.x, -sun.z)
	if enable_landmarks:
		_build_landmarks()
	if enable_beams:
		_build_beams()
	if enable_shooting_stars:
		_build_shooting_star()


func _process(delta: float) -> void:
	camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	# Everything here sits at a fixed distance from the camera, like a skybox
	global_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)

	step_clock += delta
	if step_clock < 1.0 / STEP_FPS:
		return
	var step := step_clock
	step_clock = 0.0
	if star:
		_update_star(step)
	if not beams.is_empty():
		_update_beams()
	if spinner:
		spinner.rotation.y += step * 0.35


# ---------------------------------------------------------------- landmarks

func _build_landmarks() -> void:
	# A huge pyramid on the horizon
	var pyramid := _make_pyramid(260.0, 440.0)
	pyramid.position = _horizon_point(sun_azimuth + 1.15, 1450.0, 0.0)
	add_child(pyramid)

	# A second, smaller one so it reads as a skyline instead of a lone object
	var small := _make_pyramid(150.0, 240.0)
	small.position = _horizon_point(sun_azimuth + 1.45, 1300.0, 0.0)
	add_child(small)

	# A slowly turning crystal hovering above the mountains on the other side
	spinner = _make_octahedron(110.0)
	spinner.position = _horizon_point(sun_azimuth - 1.35, 1100.0, 330.0)
	add_child(spinner)


func _horizon_point(azimuth: float, distance: float, lift: float) -> Vector3:
	return Vector3(sin(azimuth) * distance, ground_height + lift, -cos(azimuth) * distance)


func _landmark_material() -> ShaderMaterial:
	return NeonMesh.wire_material(
		Color(0.12, 0.0, 0.3), Color(0.45, 0.05, 0.5),
		Color(0.1, 0.9, 1.0), Color(1.0, 0.3, 0.9),
		ground_height, 480.0)


func _make_pyramid(half_base: float, height: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(0, height, 0)
	var corners := [
		Vector3(-half_base, 0, -half_base), Vector3(half_base, 0, -half_base),
		Vector3(half_base, 0, half_base), Vector3(-half_base, 0, half_base)]
	for i in 4:
		NeonMesh.add_wire_triangle(tool, corners[i], corners[(i + 1) % 4], apex)
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = _landmark_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _make_octahedron(radius: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, radius * 1.4, 0)
	var bottom := Vector3(0, -radius * 1.4, 0)
	var ring := [Vector3(radius, 0, 0), Vector3(0, 0, radius), Vector3(-radius, 0, 0), Vector3(0, 0, -radius)]
	for i in 4:
		NeonMesh.add_wire_triangle(tool, ring[i], ring[(i + 1) % 4], top)
		NeonMesh.add_wire_triangle(tool, ring[(i + 1) % 4], ring[i], bottom)
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	var material := NeonMesh.wire_material(
		Color(0.1, 0.0, 0.25), Color(0.4, 0.05, 0.5),
		Color(1.0, 0.85, 0.2), Color(1.0, 0.25, 0.7),
		ground_height + 150.0, 400.0)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# ---------------------------------------------------------------- light pillars

func _build_beams() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.9)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64

	beam_material = StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_material.albedo_texture = texture
	beam_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	beam_material.disable_fog = true

	var setups := [[2.1, 1150.0, Color(1.0, 0.2, 0.8)], [-2.5, 1250.0, Color(0.2, 0.9, 1.0)], [2.8, 1000.0, Color(1.0, 0.7, 0.2)]]
	for setup in setups:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 7.0
		cylinder.bottom_radius = 9.0
		cylinder.height = 1000.0
		cylinder.radial_segments = 6
		cylinder.rings = 1
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		var beam := MeshInstance3D.new()
		beam.mesh = cylinder
		var material := beam_material.duplicate() as StandardMaterial3D
		material.albedo_color = setup[2]
		beam.material_override = material
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = _horizon_point(sun_azimuth + setup[0], setup[1], 480.0)
		add_child(beam)
		beams.append(beam)


func _update_beams() -> void:
	# Pillars flicker between a few brightness steps
	for beam in beams:
		var material := beam.material_override as StandardMaterial3D
		var level := 0.6 + 0.4 * float(rng.randi_range(0, 3)) / 3.0
		material.albedo_color.a = level


# ---------------------------------------------------------------- shooting stars

func _build_shooting_star() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(0.4, 0.7, 1.0, 0.0), Color(0.8, 0.95, 1.0, 0.6), Color(1.0, 1.0, 1.0, 1.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	texture.width = 32
	texture.height = 4

	star_material = StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	star_material.albedo_texture = texture
	star_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	star_material.albedo_color = Color(2.0, 2.0, 2.0, 1.0)
	star_material.disable_fog = true

	var quad := QuadMesh.new()
	quad.size = Vector2(STAR_LENGTH, 7.0)
	star = MeshInstance3D.new()
	star.mesh = quad
	star.material_override = star_material
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.visible = false
	add_child(star)


func _update_star(step: float) -> void:
	if star_time < 0.0:
		star_wait -= step
		if star_wait <= 0.0:
			_launch_star()
		return

	star_time += step
	if star_time >= STAR_LIFETIME:
		star_time = -1.0
		star_wait = rng.randf_range(STAR_GAP.x, STAR_GAP.y)
		star.visible = false
		return

	var head := star_origin + star_direction * STAR_SPEED * star_time
	var to_camera := (camera.global_position - (global_position + head)).normalized()
	var along := (star_direction - to_camera * star_direction.dot(to_camera)).normalized()
	var up := to_camera.cross(along).normalized()
	# Local to this node; the quad's +X is the streak direction, its bright end is the head
	star.global_transform = Transform3D(Basis(along, up, to_camera), global_position + head - along * STAR_LENGTH * 0.5)
	var fade := 1.0 - maxf(star_time / STAR_LIFETIME - 0.6, 0.0) / 0.4
	star_material.albedo_color = Color(2.0, 2.0, 2.0, clampf(fade, 0.0, 1.0))


func _launch_star() -> void:
	# Spawn in the part of the sky the player is looking at
	var forward := -camera.global_basis.z
	var view_azimuth := atan2(forward.x, -forward.z)
	var azimuth := view_azimuth + rng.randf_range(-0.7, 0.7)
	var elevation := rng.randf_range(0.35, 0.8)
	var point := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	star_origin = point * STAR_DISTANCE
	# Streak sideways and downward across the sky
	var right := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	star_direction = (right * side + Vector3.DOWN * 0.45).normalized()
	star_time = 0.0
	star.visible = true
