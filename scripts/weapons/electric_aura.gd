extends Node3D

# Purely visual lightning that crackles around an enemy hit by the rifle's chain lightning.
# Child of the enemy so it follows it; no collision and no effect on movement.
# Use: ElectricAura.apply(enemy, duration)

const LIGHTNING_SHADER: Shader = preload("res://shaders/lightning.gdshader")
const ARC_COUNT := 7
const REBUILD_INTERVAL := 0.05
const BODY_HEIGHT := 1.8
const BODY_RADIUS := 0.5
const ARC_WIDTH := 0.03
const BASE_GLOW := 14.0
const FADE_TIME := 0.25

var duration := 0.7
var time_left := 0.0
var rebuild_timer := 0.0
var arc_meshes: Array[ImmediateMesh] = []
var arc_materials: Array[ShaderMaterial] = []
var glow_light: OmniLight3D


static func apply(target: Node3D, aura_duration := 0.7) -> void:
	if not is_instance_valid(target):
		return
	var existing := target.get_node_or_null("ElectricAura")
	if existing:
		existing.refresh(aura_duration)
		return
	var aura: Node3D = new()
	aura.name = "ElectricAura"
	target.add_child(aura)
	aura.refresh(aura_duration)


func refresh(aura_duration: float) -> void:
	duration = aura_duration
	time_left = aura_duration


func _ready() -> void:
	for i in ARC_COUNT:
		var mesh := ImmediateMesh.new()
		var material := ShaderMaterial.new()
		material.shader = LIGHTNING_SHADER
		material.set_shader_parameter("glow_strength", BASE_GLOW)

		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		arc_meshes.append(mesh)
		arc_materials.append(material)

	glow_light = OmniLight3D.new()
	glow_light.light_color = Color(0.4, 0.7, 1.0)
	glow_light.omni_range = 3.0
	glow_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(glow_light)

	_rebuild_arcs()


func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return

	var fade := clampf(time_left / FADE_TIME, 0.0, 1.0)
	for material in arc_materials:
		material.set_shader_parameter("glow_strength", BASE_GLOW * fade)
	glow_light.light_energy = randf_range(1.5, 4.0) * fade

	rebuild_timer -= delta
	if rebuild_timer <= 0.0:
		rebuild_timer = REBUILD_INTERVAL
		_rebuild_arcs()


func _rebuild_arcs() -> void:
	var camera := get_viewport().get_camera_3d()
	var camera_local := to_local(camera.global_position) if camera else Vector3(0.0, 1.0, 5.0)

	for mesh in arc_meshes:
		mesh.clear_surfaces()
		var points := _make_arc_points()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in points.size():
			var direction: Vector3
			if i == 0:
				direction = points[1] - points[0]
			elif i == points.size() - 1:
				direction = points[i] - points[i - 1]
			else:
				direction = points[i + 1] - points[i - 1]
			direction = direction.normalized()

			var view_direction := (camera_local - points[i]).normalized()
			var side := direction.cross(view_direction)
			if side.length_squared() < 0.0001:
				side = direction.cross(Vector3.UP)
			side = side.normalized() * ARC_WIDTH
			mesh.surface_add_vertex(points[i] - side)
			mesh.surface_add_vertex(points[i] + side)
		mesh.surface_end()


# A jagged path hugging the body: either wrapping around it or crawling up it
func _make_arc_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var steps := 9
	var jitter := 0.04

	if randf() < 0.6:
		var angle_start := randf() * TAU
		var sweep := randf_range(1.2, 2.6) * (1.0 if randf() < 0.5 else -1.0)
		var height_start := randf_range(0.1, BODY_HEIGHT - 0.2)
		var height_end := clampf(height_start + randf_range(-0.6, 0.6), 0.05, BODY_HEIGHT)
		for k in steps + 1:
			var t := float(k) / float(steps)
			var angle := angle_start + sweep * t
			var radius := BODY_RADIUS + randf_range(-0.08, 0.12)
			points.append(Vector3(cos(angle) * radius, lerpf(height_start, height_end, t), sin(angle) * radius) + _jitter(jitter))
	else:
		var angle_base := randf() * TAU
		var height_start := randf_range(0.0, 0.5)
		var height_end := height_start + randf_range(0.9, 1.4)
		for k in steps + 1:
			var t := float(k) / float(steps)
			var angle := angle_base + randf_range(-0.3, 0.3)
			var radius := BODY_RADIUS + randf_range(-0.05, 0.12)
			points.append(Vector3(cos(angle) * radius, lerpf(height_start, height_end, t), sin(angle) * radius) + _jitter(jitter))

	return points


func _jitter(amount: float) -> Vector3:
	return Vector3(randf_range(-amount, amount), randf_range(-amount, amount), randf_range(-amount, amount))
