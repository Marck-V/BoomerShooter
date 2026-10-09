extends Node3D

# More sky scenery layered on top of the sunset: a ringed planet, an aurora,
# distant lightning and rays fanning out from the sun. Like the rest of the backdrop it follows
# the camera (so it never gets closer) and moves in stepped, low-framerate motion.
# Each effect can be switched off with its flag before the node enters the tree.

const PLANET_SHADER: Shader = preload("res://shaders/planet.gdshader")
const AURORA_SHADER: Shader = preload("res://shaders/aurora.gdshader")

var ground_height := -90.0
var sun_direction := Vector3(-0.3, 0.12, -1.0)
var random_seed := 7

var enable_planet := true
var enable_aurora := true
var enable_lightning := true
var enable_god_rays := true

const STEP_FPS := 12.0
const SUN_RADIUS := 0.2
const RAY_DISTANCE := 1700.0

var rng := RandomNumberGenerator.new()
var sun_azimuth := 0.0
var step_clock := 0.0
var flash: MeshInstance3D
var flash_wait := 5.0
var flash_time := -1.0
var rays: MeshInstance3D
var ray_material: StandardMaterial3D
var ray_angle := 0.0


func _ready() -> void:
	top_level = true
	rng.seed = random_seed + 23
	var sun := sun_direction.normalized()
	sun_azimuth = atan2(sun.x, -sun.z)
	if enable_planet:
		_build_planet()
	if enable_aurora:
		_build_aurora()
	if enable_lightning:
		_build_lightning()
	if enable_god_rays:
		_build_god_rays()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
	if rays:
		_align_god_rays(camera)

	step_clock += delta
	if step_clock < 1.0 / STEP_FPS:
		return
	var step := step_clock
	step_clock = 0.0
	_update_lightning(step)
	_update_god_rays(step)


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_fog = true
	return material


func _sky_point(azimuth: float, distance: float, lift: float) -> Vector3:
	return Vector3(sin(azimuth) * distance, ground_height + lift, -cos(azimuth) * distance)


# ---------------------------------------------------------------- planet

func _build_planet() -> void:
	var azimuth := sun_azimuth - 1.05
	var position_in_sky := _sky_point(azimuth, 1650.0, 800.0)

	var sphere := SphereMesh.new()
	sphere.radius = 170.0
	sphere.height = 340.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var material := ShaderMaterial.new()
	material.shader = PLANET_SHADER
	var planet := MeshInstance3D.new()
	planet.mesh = sphere
	planet.material_override = material
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.position = position_in_sky
	add_child(planet)

	var torus := TorusMesh.new()
	torus.inner_radius = 250.0
	torus.outer_radius = 330.0
	torus.rings = 24
	torus.ring_segments = 3
	var ring_material := _unshaded(Color(0.85, 0.95, 1.0, 0.8))
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.03, 1.0)
	ring.rotation_degrees = Vector3(18.0, 0.0, -24.0)
	ring.position = position_in_sky
	add_child(ring)


# ---------------------------------------------------------------- aurora

func _build_aurora() -> void:
	var center := sun_azimuth + PI * 0.92
	var span := 1.9
	var columns := 64
	var rows := 5
	var radius := 1750.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for c in columns + 1:
		var u := float(c) / columns
		var azimuth := center - span * 0.5 + span * u
		var column: Array[Vector3] = []
		for r in rows + 1:
			var v := float(r) / rows
			var sway := sin(u * 9.0) * 110.0 + sin(u * 4.0 + 1.0) * 70.0
			column.append(_sky_point(azimuth, radius, 520.0 + sway + v * 520.0))
		grid.append(column)
	for c in columns:
		for r in rows:
			var uv_a := Vector2(float(c) / columns, float(r) / rows)
			var uv_b := Vector2(float(c + 1) / columns, float(r) / rows)
			var uv_c := Vector2(float(c) / columns, float(r + 1) / rows)
			var uv_d := Vector2(float(c + 1) / columns, float(r + 1) / rows)
			var quad: Array = [
				[grid[c][r], uv_a], [grid[c][r + 1], uv_c], [grid[c + 1][r], uv_b],
				[grid[c + 1][r], uv_b], [grid[c][r + 1], uv_c], [grid[c + 1][r + 1], uv_d]]
			for vertex in quad:
				tool.set_uv(vertex[1])
				tool.add_vertex(vertex[0])
	var aurora := MeshInstance3D.new()
	aurora.mesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = AURORA_SHADER
	aurora.material_override = material
	aurora.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aurora)


# ---------------------------------------------------------------- lightning

func _build_lightning() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 0.95, 1.0, 1.0), Color(0.7, 0.4, 1.0, 0.6), Color(0.4, 0.1, 0.8, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var material := _unshaded(Color(2.0, 1.6, 2.2, 1.0))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2(650.0, 650.0)
	flash = MeshInstance3D.new()
	flash.mesh = quad
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	add_child(flash)


func _update_lightning(step: float) -> void:
	if flash_time < 0.0:
		flash_wait -= step
		if flash_wait <= 0.0:
			flash_time = 0.0
			flash.position = _sky_point(rng.randf_range(0.0, TAU), rng.randf_range(1300.0, 1600.0), rng.randf_range(120.0, 380.0))
		return
	flash_time += step
	# Flicker: on, off, on, fade out
	flash.visible = flash_time < 0.09 or (flash_time > 0.16 and flash_time < 0.34)
	if flash_time > 0.4:
		flash_time = -1.0
		flash.visible = false
		flash_wait = rng.randf_range(6.0, 14.0)


# ---------------------------------------------------------------- god rays

func _build_god_rays() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 9
	var length := 1500.0
	# Edge of the sun disc as seen from the camera: sun_radius (0.2 rad, see synthwave_sky.gdshader) at the ray distance
	var rim := tan(SUN_RADIUS) * RAY_DISTANCE
	for i in count:
		var angle := TAU * float(i) / count
		var half_width := 0.075
		var center_color := Color(1.0, 0.75, 0.35, 0.34)
		var edge_color := Color(1.0, 0.4, 0.3, 0.0)
		# Rays start at the rim of the sun disc (not its center) so they never cross the sun itself
		var inner := Vector3(cos(angle - half_width), sin(angle - half_width), 0.0)
		var inner_b := Vector3(cos(angle + half_width), sin(angle + half_width), 0.0)
		for vertex in [[inner * rim, center_color], [inner * length, edge_color], [inner_b * rim, center_color],
				[inner_b * rim, center_color], [inner * length, edge_color], [inner_b * length, edge_color]]:
			tool.set_color(vertex[1])
			tool.add_vertex(vertex[0])
	ray_material = _unshaded(Color(1.6, 1.2, 1.0, 1.0))
	ray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ray_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ray_material.vertex_color_use_as_albedo = true
	rays = MeshInstance3D.new()
	rays.mesh = tool.commit()
	rays.material_override = ray_material
	rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rays)


# Per frame: stay centered on the sun (as seen from the camera) and face the camera
func _align_god_rays(camera: Camera3D) -> void:
	rays.global_position = camera.global_position + sun_direction.normalized() * RAY_DISTANCE
	rays.look_at(camera.global_position, Vector3.UP)
	rays.rotate_object_local(Vector3(0, 0, 1), ray_angle)


# Stepped: slow rotation and a flicker in strength
func _update_god_rays(step: float) -> void:
	if rays == null:
		return
	ray_angle += step * 0.05
	ray_material.albedo_color = Color(1.6, 1.2, 1.0, 0.65 + 0.35 * float(rng.randi_range(0, 3)) / 3.0)
