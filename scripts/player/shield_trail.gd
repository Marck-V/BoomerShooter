extends Node3D

# Glowing ribbon behind the thrown shield, built from its recent positions in world space.
# Points expire with time, so the trail shrinks away when the shield stops (for example on a grapple point).
# While the shield carries a parry streak (Retaliation) the trail is blue and a little wider, the same cyan-white as the
# charged glow on the shield. Each point remembers how empowered the shield was when it was laid down, so the blue stays
# behind the throw and the trail goes back to gold after the empowered hit.

const LIFETIME := 0.3          # seconds a point of the trail lives
const WIDTH := 0.13
const MIN_STEP := 0.04         # meters the shield must move before a new point is added
const EMPOWERED_WIDTH := 0.6   # extra width at full empowerment, as a fraction of WIDTH

var target: Node3D
var empower := 0.0             # 0: a normal throw; above 0: carrying a streak (up to 1 for a full one). Set by the shield.
var points: Array[Vector3] = []
var born: Array[float] = []
var powers: Array[float] = []
var mesh: ImmediateMesh                  # the gold part of the trail
var power_mesh: ImmediateMesh            # the blue part
var instance: MeshInstance3D
var power_instance: MeshInstance3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = ImmediateMesh.new()
	instance = _make_instance(mesh, Color(1.4, 1.1, 0.7))
	power_mesh = ImmediateMesh.new()
	power_instance = _make_instance(power_mesh, Color(0.9, 1.5, 2.0))


func _make_instance(immediate: ImmediateMesh, tint: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = tint
	material.disable_fog = true
	var node := MeshInstance3D.new()
	node.mesh = immediate
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if is_instance_valid(target):
		var here := target.global_position
		if points.is_empty() or here.distance_to(points[0]) >= MIN_STEP:
			points.push_front(here)
			born.push_front(now)
			powers.push_front(empower)
	while not born.is_empty() and now - born[born.size() - 1] > LIFETIME:
		born.pop_back()
		points.pop_back()
		powers.pop_back()
	_rebuild(now)


func _rebuild(now: float) -> void:
	mesh.clear_surfaces()
	power_mesh.clear_surfaces()
	var count := points.size()
	if count < 2 or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	# The head follows the shield exactly so there is no gap, even between recorded points
	var head := target.global_position

	# Runs of points with the same look become one strip each; neighbouring runs share their boundary point so there is
	# no gap where the colour changes
	var run_start := 0
	while run_start < count - 1:
		var empowered := powers[run_start] > 0.0
		var run_end := run_start + 1
		while run_end < count - 1 and (powers[run_end] > 0.0) == empowered:
			run_end += 1
		var target_mesh := power_mesh if empowered else mesh
		target_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(run_start, run_end + 1):
			_add_pair(target_mesh, i, count, head, camera, now, empowered)
		target_mesh.surface_end()
		run_start = run_end


# The two vertices of the ribbon at point i
func _add_pair(into: ImmediateMesh, i: int, count: int, head: Vector3, camera: Camera3D, now: float, empowered: bool) -> void:
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
	var width := WIDTH * (1.0 + EMPOWERED_WIDTH * powers[i]) if empowered else WIDTH
	side = side.normalized() * width * pow(fade, 1.6)
	var color: Color
	if empowered:
		# Pale cyan-white at the head, through blue, fading out
		color = Color(0.75, 0.98, 1.0, fade * fade).lerp(Color(0.12, 0.42, 1.0, fade * fade * 0.85), clampf(age * 1.8, 0.0, 1.0))
	else:
		# Hot pale yellow at the head, through orange, fading out
		color = Color(1.0, 0.95, 0.6, fade * fade).lerp(Color(1.0, 0.5, 0.05, fade * fade * 0.8), clampf(age * 1.8, 0.0, 1.0))
	into.surface_set_color(color)
	into.surface_add_vertex(point - side)
	into.surface_set_color(color)
	into.surface_add_vertex(point + side)
