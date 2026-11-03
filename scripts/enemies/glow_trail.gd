extends MeshInstance3D

# Bright ribbon that follows source, built from its recent positions (world space) and always turned to the camera.
# While inactive it stops growing and shrinks away from the tail.

const SHRINK_INTERVAL := 0.02

var source: Node3D
var active := true
var head_color := Color.WHITE
var tail_color := Color.WHITE
var max_points := 8
var spacing := 0.25
var width := 0.1                  # at the head, at the source's scale of 1
var brightness := 2.4:
	set(value):
		brightness = value
		if material_override:
			material_override.albedo_color = Color(value, value, value)

var ribbon := ImmediateMesh.new()
var points: Array[Vector3] = []
var shrink_timer := 0.0


func _ready() -> void:
	mesh = ribbon
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(brightness, brightness, brightness)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if active:
		if points.is_empty() or source.global_position.distance_to(points[0]) >= spacing:
			points.push_front(source.global_position)
			if points.size() > max_points:
				points.pop_back()
	elif points.is_empty():
		return
	else:
		shrink_timer -= delta
		if shrink_timer <= 0.0:
			shrink_timer = SHRINK_INTERVAL
			points.pop_back()
	_rebuild()


func _rebuild() -> void:
	ribbon.clear_surfaces()
	var count := points.size()
	if count < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var head := source.global_position if active else points[0]
	var head_width := width * source.global_basis.x.length()
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var point := head if i == 0 else points[i]
		var next_point := points[i + 1] if i < count - 1 else point
		var previous_point := head if i == 0 else points[i - 1]
		var direction := (previous_point - next_point).normalized()
		if direction.length_squared() < 0.0001:
			direction = Vector3.FORWARD
		var to_camera := (camera.global_position - point).normalized() if camera else Vector3.UP
		var side := direction.cross(to_camera)
		if side.length_squared() < 0.0001:
			side = direction.cross(Vector3.UP)
		var fade := 1.0 - float(i) / float(count - 1)
		side = side.normalized() * head_width * fade
		var color := tail_color.lerp(head_color, fade)
		color.a = fade
		ribbon.surface_set_color(color)
		ribbon.surface_add_vertex(point - side)
		ribbon.surface_set_color(color)
		ribbon.surface_add_vertex(point + side)
	ribbon.surface_end()
