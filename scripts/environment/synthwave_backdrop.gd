extends Node3D

# Sunset-outrun scenery around the level: a neon grid floor far below, wireframe mountains,
# and floating rock islands with palm trees. All low-poly, flat shaded and built in code.
# The grid and mountains follow the player camera so they behave like an endless horizon;
# the islands stay put in the world and bob in stepped, low-framerate motion.

const NeonMesh = preload("res://scripts/environment/neon_mesh.gd")
const SkyEffects = preload("res://scripts/environment/sky_effects.gd")
const SkyExtras = preload("res://scripts/environment/sky_extras.gd")
const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")
const AmbientParticles = preload("res://scripts/environment/ambient_particles.gd")
const NEON_GRID: Shader = preload("res://shaders/neon_grid.gdshader")

@export var ground_height := -90.0
@export var sun_direction := Vector3(-0.3, 0.12, -1.0)
@export var mountain_inner_radius := 650.0
@export var mountain_outer_radius := 1500.0
@export var mountain_height := 280.0
@export var island_count := 9
@export var random_seed := 7

@export_group("Effects (untick to remove)")
@export var shooting_stars := true
@export var horizon_landmarks := true
@export var light_pillars := true
@export var planet := true
@export var aurora := true
@export var distant_lightning := true
@export var sun_rays := true
@export var floating_motes := true
@export var wind_streaks := true
@export var island_debris := true
@export var sun_light_color := Color(1.0, 0.6, 0.4)
@export var sun_light_energy := 1.6

const MOUNTAIN_RINGS := 7
const MOUNTAIN_SEGMENTS := 200
const BOB_FPS := 12.0

var ground: MeshInstance3D
var mountains: MeshInstance3D
var islands: Array[Node3D] = []
var island_base_y: Array[float] = []
var island_phase: Array[float] = []
var level_center := Vector3.ZERO
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	rng.seed = random_seed
	level_center = _find_level_center()
	_build_ground()
	_build_mountains()
	_build_islands()
	_sync_sun_light()

	var effects := SkyEffects.new()
	effects.ground_height = ground_height
	effects.sun_direction = sun_direction
	effects.random_seed = random_seed
	effects.enable_shooting_stars = shooting_stars
	effects.enable_landmarks = horizon_landmarks
	effects.enable_beams = light_pillars
	add_child(effects)

	var extras := SkyExtras.new()
	extras.ground_height = ground_height
	extras.sun_direction = sun_direction
	extras.random_seed = random_seed
	extras.enable_planet = planet
	extras.enable_aurora = aurora
	extras.enable_lightning = distant_lightning
	extras.enable_god_rays = sun_rays
	add_child(extras)

	var motes := AmbientParticles.new()
	motes.enable_motes = floating_motes
	motes.enable_streaks = wind_streaks
	add_child(motes)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		var follow := Vector3(camera.global_position.x, 0.0, camera.global_position.z)
		ground.global_position = follow + Vector3(0, ground_height, 0)
		mountains.global_position = follow

	var time := floorf(Time.get_ticks_msec() / 1000.0 * BOB_FPS) / BOB_FPS
	for i in islands.size():
		islands[i].position.y = island_base_y[i] + sin(time * 0.5 + island_phase[i]) * 2.0
		islands[i].rotation.y = sin(time * 0.1 + island_phase[i]) * 0.15


# Points the level's directional light along the sun in the sky so lit surfaces match it
func _sync_sun_light() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		var toward := -sun_direction.normalized()
		var up := Vector3.UP if absf(toward.y) < 0.99 else Vector3.RIGHT
		light.global_transform = Transform3D(Basis.looking_at(toward, up), light.global_position)
		light.light_color = sun_light_color
		light.light_energy = sun_light_energy


func _find_level_center() -> Vector3:
	var box := AABB()
	var first := true
	var scene := get_tree().current_scene
	if scene == null:
		return Vector3.ZERO
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or not scene.is_ancestor_of(mesh_instance) or is_ancestor_of(mesh_instance):
			continue
		if mesh_instance.is_in_group("Enemy"):
			continue
		var bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		if bounds.size.length() > 400.0:
			continue
		box = bounds if first else box.merge(bounds)
		first = false
	return box.get_center() if not first else Vector3.ZERO


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(7000, 7000)
	var material := ShaderMaterial.new()
	material.shader = NEON_GRID
	ground = MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


# ---------------------------------------------------------------- mountains

func _build_mountains() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.frequency = 0.0032
	var sun := sun_direction.normalized()
	var sun_azimuth := atan2(sun.x, -sun.z)

	var heights := PackedFloat32Array()
	heights.resize((MOUNTAIN_RINGS + 1) * (MOUNTAIN_SEGMENTS + 1))
	var positions: Array[Vector3] = []
	for ring in MOUNTAIN_RINGS + 1:
		var ring_t := float(ring) / MOUNTAIN_RINGS
		var radius := lerpf(mountain_inner_radius, mountain_outer_radius, ring_t)
		for seg in MOUNTAIN_SEGMENTS + 1:
			var angle := TAU * float(seg % MOUNTAIN_SEGMENTS) / MOUNTAIN_SEGMENTS
			var x := sin(angle) * radius
			var z := -cos(angle) * radius
			var ridge := pow(noise.get_noise_2d(x, z) * 0.5 + 0.5, 1.7)
			# Keep a low valley in front of the sun so the whole disc stays visible
			var away := absf(wrapf(angle - sun_azimuth, -PI, PI))
			var valley := 0.12 + 0.88 * smoothstep(0.1, 0.7, away)
			var taper := pow(sin(PI * ring_t), 0.6)
			positions.append(Vector3(x, ground_height + mountain_height * ridge * valley * taper, z))

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride := MOUNTAIN_SEGMENTS + 1
	for ring in MOUNTAIN_RINGS:
		for seg in MOUNTAIN_SEGMENTS:
			var a := positions[ring * stride + seg]
			var b := positions[ring * stride + seg + 1]
			var c := positions[(ring + 1) * stride + seg]
			var d := positions[(ring + 1) * stride + seg + 1]
			NeonMesh.add_wire_triangle(tool, a, c, b)
			NeonMesh.add_wire_triangle(tool, b, c, d)

	mountains = MeshInstance3D.new()
	mountains.mesh = tool.commit()
	mountains.material_override = NeonMesh.wire_material(
		Color(0.02, 0.0, 0.1), Color(0.18, 0.0, 0.3),
		Color(0.15, 0.3, 1.0), Color(1.0, 0.2, 0.9),
		ground_height, mountain_height)
	mountains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mountains)


# ---------------------------------------------------------------- floating islands

func _build_islands() -> void:
	var sun := sun_direction.normalized()
	var sun_azimuth := atan2(sun.x, -sun.z)
	for i in island_count:
		# The first few sit in front of the sun so they cut silhouettes across the disc
		var angle: float
		if i < 4:
			angle = sun_azimuth + [-0.5, -0.17, 0.18, 0.5][i] + rng.randf_range(-0.05, 0.05)
		else:
			angle = rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(300.0, 470.0)
		var island_position := level_center + Vector3(sin(angle) * distance, rng.randf_range(-15.0, 60.0), -cos(angle) * distance)
		var island := _make_island(rng.randf_range(24.0, 48.0))
		island.position = island_position
		add_child(island)
		islands.append(island)
		island_base_y.append(island_position.y)
		island_phase.append(rng.randf_range(0.0, TAU))


func _make_island(radius: float) -> Node3D:
	var root := Node3D.new()
	var sides := 11
	var depth := radius * rng.randf_range(1.0, 1.5)

	var rim: Array[Vector3] = []
	var lower: Array[Vector3] = []
	var tip := Vector3(rng.randf_range(-2.0, 2.0), -depth, rng.randf_range(-2.0, 2.0))
	for i in sides:
		var angle := TAU * float(i) / sides
		var jitter := rng.randf_range(0.8, 1.15)
		rim.append(Vector3(cos(angle) * radius * jitter, rng.randf_range(-0.5, 0.5), sin(angle) * radius * jitter))
		var inner_jitter := rng.randf_range(0.7, 1.0)
		lower.append(Vector3(cos(angle + 0.25) * radius * 0.55 * inner_jitter, -depth * 0.55, sin(angle + 0.25) * radius * 0.55 * inner_jitter))

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var j := (i + 1) % sides
		NeonMesh.add_wire_triangle(tool, Vector3.ZERO, rim[j], rim[i])                 # top
		NeonMesh.add_wire_triangle(tool, rim[i], rim[j], lower[i])                     # side band
		NeonMesh.add_wire_triangle(tool, rim[j], lower[j], lower[i])
		NeonMesh.add_wire_triangle(tool, lower[i], lower[j], tip)                      # underside point

	var rock := MeshInstance3D.new()
	rock.mesh = tool.commit()
	rock.material_override = NeonMesh.wire_material(
		Color(0.03, 0.0, 0.14), Color(0.1, 0.0, 0.3),
		Color(0.1, 0.8, 1.0), Color(1.0, 0.25, 0.9),
		-radius * 1.5, radius * 2.0)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rock)

	if island_debris:
		root.add_child(_make_debris(radius))

	for i in rng.randi_range(1, 3):
		var palm := _make_palm(rng.randf_range(22.0, 34.0))
		var angle := rng.randf_range(0.0, TAU)
		var spot := rng.randf_range(0.0, radius * 0.55)
		palm.position = Vector3(cos(angle) * spot, 0.0, sin(angle) * spot)
		palm.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(palm)
	return root


# Chunks that crumble off the underside and drift down
func _make_debris(radius: float) -> GPUParticles3D:
	var debris := FlameParticles.make_emitter({
		"amount": 9, "lifetime": 7.0, "texture": null,
		"size": 1.4, "speed": Vector2(0.0, 0.6), "damping": Vector2(0.0, 0.0),
		"spread": 40.0, "gravity": Vector3(0, -2.2, 0),
		"direction": Vector3.DOWN, "box": Vector3(radius * 0.35, 0.5, radius * 0.35),
		"scale_curve": [Vector2(0.0, 1.0), Vector2(0.8, 0.8), Vector2(1.0, 0.0)],
		"colors": [
			[0.0, Color(0.55, 0.2, 0.9, 1.0)],
			[0.5, Color(0.9, 0.25, 0.8, 1.0)],
		],
	})
	debris.position = Vector3(0, -radius * 0.7, 0)
	debris.preprocess = 7.0
	debris.emitting = true
	return debris


# ---------------------------------------------------------------- palm trees

func _make_palm(height: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_dark := Color(0.02, 0.09, 0.15)
	var trunk_light := Color(0.05, 0.22, 0.3)
	var leaf_dark := Color(0.02, 0.12, 0.17)
	var leaf_light := Color(0.1, 0.5, 0.55)

	# Curved trunk as a short low-poly tube
	var bend := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * height * 0.22
	var segments := 8
	var sides := 5
	var rings: Array = []
	var top := Vector3.ZERO
	for i in segments + 1:
		var t := float(i) / segments
		var center := Vector3(bend.x * t * t, height * t, bend.z * t * t)
		var trunk_radius := lerpf(0.5, 0.25, t)
		var ring: Array[Vector3] = []
		for s in sides:
			var angle := TAU * float(s) / sides
			ring.append(center + Vector3(cos(angle), 0.0, sin(angle)) * trunk_radius)
		rings.append(ring)
		top = center
	for i in segments:
		for s in sides:
			var n := (s + 1) % sides
			var color := trunk_dark.lerp(trunk_light, float(i) / segments)
			var a: Vector3 = rings[i][s]
			var b: Vector3 = rings[i][n]
			var c: Vector3 = rings[i + 1][s]
			var d: Vector3 = rings[i + 1][n]
			for vertex in [a, c, b, b, c, d]:
				tool.set_color(color)
				tool.add_vertex(vertex)

	# Feathery fronds fanning out from the crown
	var frond_count := 9
	var frond_length := height * 0.55
	for f in frond_count:
		var yaw := TAU * float(f) / frond_count + rng.randf_range(-0.2, 0.2)
		var outward := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var length := frond_length * rng.randf_range(0.85, 1.15)
		var lift := rng.randf_range(0.45, 0.8)
		var previous := top
		for k in range(1, 8):
			var s := float(k) / 7.0
			var spine := top + outward * (s * length) + Vector3.UP * (length * (lift * s - 0.8 * s * s))
			var leaf_width := lerpf(2.4, 0.5, s) * (length / frond_length)
			var drop := Vector3.DOWN * leaf_width * 0.7
			var forward := (spine - previous).normalized()
			var color := leaf_dark.lerp(leaf_light, s)
			for sign in [-1.0, 1.0]:
				var tip: Vector3 = spine + side * sign * leaf_width + drop + forward * 0.6
				for vertex in [previous, spine, tip]:
					tool.set_color(color)
					tool.add_vertex(vertex)
			previous = spine

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true

	var palm := MeshInstance3D.new()
	palm.mesh = tool.commit()
	palm.material_override = material
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return palm
