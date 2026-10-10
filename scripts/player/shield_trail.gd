extends Node3D

# Glowing ribbon behind the thrown shield, built from its recent positions in world space.
# Points expire with time, so the trail shrinks away when the shield stops (for example on a grapple point).

const LIFETIME := 0.3          # seconds a point of the trail lives
const WIDTH := 0.13
const MIN_STEP := 0.04         # meters the shield must move before a new point is added

var target: Node3D
var points: Array[Vector3] = []
var born: Array[float] = []
var mesh: ImmediateMesh
var instance: MeshInstance3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.4, 1.1, 0.7)
	material.disable_fog = true
	instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if is_instance_valid(target):
		var here := target.global_position
		if points.is_empty() or here.distance_to(points[0]) >= MIN_STEP:
			points.push_front(here)
			born.push_front(now)
	while not born.is_empty() and now - born[born.size() - 1] > LIFETIME:
		born.pop_back()
		points.pop_back()
	_rebuild(now)


func _rebuild(now: float) -> void:
	mesh.clear_surfaces()
	var count := points.size()
	if count < 2 or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	# The head follows the shield exactly so there is no gap, even between recorded points
	var head := target.global_position
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
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
		var age := clampf((now - born[i]) / LIFETIME, 0.0, 1.0)
		var fade := 1.0 - age
		side = side.normalized() * WIDTH * pow(fade, 1.6)
		# Hot pale yellow at the head, through orange, fading out
		var color := Color(1.0, 0.95, 0.6, fade * fade).lerp(Color(1.0, 0.5, 0.05, fade * fade * 0.8), clampf(age * 1.8, 0.0, 1.0))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(point - side)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(point + side)
	mesh.surface_end()
