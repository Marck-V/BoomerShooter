extends Node3D

# Lightning, shared by everything electric: the lightning gun's shot and chain, the crackle on enemies it hits, and the
# arcs on the gun model.
#
# Shapes are fractal (bent at every scale, each smaller bend gentler than the one above it) with side branches that
# thin out and fade. They are drawn as camera-facing ribbons with shaders/player/lightning_bolt.gdshader: a white core in a
# blue-to-violet glow.
#
# A strike (LightningBolt.strike()) lives about a quarter of a second: it re-strikes a few times in a fresh shape,
# flickering as it dies, flashes a light where it lands and throws sparks there.
#
# The static functions (fractal, roughen, add_ribbon, new_material) are for code that draws its own arcs, like the
# electric aura and the gun's model.

const SHADER: Shader = preload("res://shaders/player/lightning_bolt.gdshader")

const DEFAULTS := {
	"width": 0.12,            # half-width of the glow in metres; the white core is a fraction of it
	"start_width": -1.0,      # if set, the bolt starts this thin and swells to `width` over `start_ramp` metres
	"start_ramp": 4.0,
	"branches": -1,           # side branches; -1 picks a number from the bolt's length
	"detail": 0.05,           # how far the biggest bend strays, as a share of the bolt's length...
	"max_bend": 0.45,         # ...but never more than this many metres, so long bolts stay on course
	"time": 0.26,             # seconds the strike lasts
	"restrikes": 3,           # fresh shapes over its life
	"light": true,            # a flash of light where it lands (and halfway along a long bolt)
	"sparks": true,           # a burst of sparks where it lands
	"energy": 5.0,
	"follow": null,           # a Node3D (the gun's muzzle) the bolt's start stays on while it lives; the end stays put
}
const LIGHT_COLOR := Color(0.45, 0.55, 1.0)
const LIGHT_ENERGY := 5.0
const LIGHT_RANGE := 5.0
const SPARK_COUNT := 18
const SPARK_LIFETIME := 0.35

var start := Vector3.ZERO
var end := Vector3.ZERO
var settings := {}
var mesh: ImmediateMesh
var material: ShaderMaterial
var lights: Array[OmniLight3D] = []
var age := 0.0
var strike_index := -1
# The current shape, kept so it can be redrawn when the start moves: each path is
# {points, widths, alphas, along} where `along` is how far each point is from start (0) to end (1)
var _paths: Array[Dictionary] = []
var _built_start := Vector3.ZERO


# Fires a bolt from start to end (world positions). `options` overrides any of DEFAULTS. Returns the bolt's node.
static func strike(tree: SceneTree, from: Vector3, to: Vector3, options := {}) -> Node3D:
	var bolt = new()
	bolt.start = from
	bolt.end = to
	bolt.settings = DEFAULTS.duplicate()
	bolt.settings.merge(options, true)
	var parent := tree.current_scene if tree.current_scene else tree.root
	parent.add_child(bolt)
	return bolt


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = ImmediateMesh.new()
	material = new_material(settings["energy"])
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 16384.0   # the mesh is rebuilt every strike; never let it be culled
	add_child(instance)

	if settings["light"]:
		lights.append(_make_light(end))
		if start.distance_to(end) > 8.0:
			lights.append(_make_light(start.lerp(end, 0.55)))
	if settings["sparks"]:
		_spawn_sparks()


func _process(delta: float) -> void:
	age += delta
	var life: float = settings["time"]
	if age >= maxf(life, SPARK_LIFETIME + 0.05):
		queue_free()
		return
	if age >= life:
		mesh.clear_surfaces()
		for light in lights:
			light.light_energy = 0.0
		return

	# A fresh shape at every restrike; each one starts bright and fades fast, with the odd dark frame: a strobe
	var follow = settings["follow"]   # untyped: it may have been freed (weapon swap, death)
	if follow != null and is_instance_valid(follow):
		start = (follow as Node3D).global_position
	var restrikes: int = settings["restrikes"]
	var slot := life / restrikes
	var index := mini(int(age / slot), restrikes - 1)
	if index != strike_index:
		strike_index = index
		_build()
	elif follow != null:
		_draw()   # same shape, pulled along to where the muzzle is now
	var into_slot := (age - slot * index) / slot
	var peak := 1.0 - 0.25 * index
	var level := peak * lerpf(1.0, 0.3, into_slot)
	if randf() < 0.12:
		level *= 0.2
	material.set_shader_parameter("intensity", level)
	for light in lights:
		light.light_energy = LIGHT_ENERGY * level


func _build() -> void:
	var width: float = settings["width"]
	var length := start.distance_to(end)

	var detail := minf(settings["detail"], settings["max_bend"] / maxf(length, 0.01))
	var main := fractal(start, end, detail, maxf(length / 32.0, 0.08))
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	var start_width: float = settings["start_width"]
	for i in main.size():
		var t := float(i) / (main.size() - 1)
		var w := width * lerpf(1.0, 0.75, t)                              # a little thinner where it lands
		if start_width >= 0.0:
			w = lerpf(start_width, w, clampf(main[i].distance_to(start) / settings["start_ramp"], 0.0, 1.0))
		widths.append(w)
		alphas.append(1.0)

	_built_start = start
	_paths.clear()
	_add_path(main, widths, alphas)

	var branch_count: int = settings["branches"]
	if branch_count < 0:
		branch_count = clampi(int(length / 5.0), 0, 3)
	var direction := (end - start).normalized()
	for b in branch_count:
		var at := randi_range(int(main.size() * 0.3), int(main.size() * 0.85))   # not right at the gun
		var origin := main[at]
		var axis := direction.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
		if axis.length_squared() < 0.5:
			continue
		var heading := direction.rotated(axis, deg_to_rad(randf_range(15.0, 35.0)))
		var reach := minf(length * randf_range(0.06, 0.16), 2.0)
		var branch := fractal(origin, origin + heading * reach, 0.12, maxf(reach / 12.0, 0.05))
		var branch_widths := PackedFloat32Array()
		var branch_alphas := PackedFloat32Array()
		for i in branch.size():
			var t := float(i) / (branch.size() - 1)
			branch_widths.append(widths[at] * lerpf(0.55, 0.15, t))
			branch_alphas.append(lerpf(0.8, 0.0, t))
		_add_path(branch, branch_widths, branch_alphas)
	_draw()


func _add_path(points: Array[Vector3], widths: PackedFloat32Array, alphas: PackedFloat32Array) -> void:
	var line := end - start
	var length_squared := maxf(line.length_squared(), 0.0001)
	var along := PackedFloat32Array()
	for point in points:
		along.append(clampf((point - start).dot(line) / length_squared, 0.0, 1.0))
	_paths.append({"points": points, "widths": widths, "alphas": alphas, "along": along})


# Draws the current shape. If the start has moved since it was built (it follows the muzzle), every point shifts by
# that much, fading to nothing at the far end, so the bolt stays on the barrel while the end stays where it landed.
func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else start + Vector3.UP * 5.0
	var moved := start - _built_start
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for path in _paths:
		var points: Array[Vector3] = path["points"]
		var along: PackedFloat32Array = path["along"]
		var shifted: Array[Vector3] = []
		for i in points.size():
			shifted.append(points[i] + moved * (1.0 - along[i]))
		add_ribbon(mesh, shifted, path["widths"], path["alphas"], eye)
	mesh.surface_end()


func _make_light(at: Vector3) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at
	return light


func _spawn_sparks() -> void:
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.vertex_color_use_as_albedo = true
	spark_material.albedo_color = Color(2.5, 3.0, 4.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = spark_material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.6, 0.6, 1.0, 0.8), Color(0.5, 0.3, 1.0, 0.0)])

	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = SPARK_COUNT
	sparks.lifetime = SPARK_LIFETIME
	sparks.mesh = quad
	sparks.direction = (start - end).normalized()   # back towards where the bolt came from
	sparks.spread = 75.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 6.0
	sparks.gravity = Vector3(0.0, -12.0, 0.0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.3
	sparks.color_ramp = fade
	add_child(sparks)
	sparks.global_position = end
	sparks.emitting = true


# ---------------------------------------------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------------------------------------------

# A ShaderMaterial for drawing bolts. Each user gets its own so it can strobe it.
static func new_material(energy := 5.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("energy", energy)
	return mat


# A jagged path from a to b by midpoint displacement: every segment is split at a point pushed off sideways, the push
# shrinking at each finer level, until segments are shorter than min_segment. detail is the first push as a share of
# the length (so a straight-ish bolt wants something like 0.05; a short twitchy arc 0.2). max_offset, if given, keeps every point within that distance of the straight line (for arcs that must
# stay inside something).
static func fractal(a: Vector3, b: Vector3, detail := 0.11, min_segment := 0.1, max_offset := INF) -> Array[Vector3]:
	var span := b - a
	var length := span.length()
	var points: Array[Vector3] = [a, b]
	if length < 0.0001:
		return points
	var direction := span / length
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := direction.cross(side).normalized()

	var push := length * detail
	var segment := length
	for depth in 8:
		if segment < min_segment:
			break
		var refined: Array[Vector3] = []
		for i in points.size() - 1:
			var mid := (points[i] + points[i + 1]) * 0.5
			mid += side * randf_range(-push, push) + up * randf_range(-push, push)
			refined.append(points[i])
			refined.append(mid)
		refined.append(points[-1])
		points = refined
		push *= 0.55
		segment *= 0.5

	if max_offset < INF:
		for i in points.size():
			var along := (points[i] - a).dot(direction)
			var on_line := a + direction * along
			var off := points[i] - on_line
			if off.length() > max_offset:
				points[i] = on_line + off.normalized() * max_offset
	return points


# Fractal detail between each pair of control points of a hand-shaped path (like the aura's arcs round a body)
static func roughen(control: Array[Vector3], detail := 0.25, min_segment := 0.05) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in control.size() - 1:
		var piece := fractal(control[i], control[i + 1], detail, min_segment)
		if i > 0:
			piece.remove_at(0)
		points.append_array(piece)
	return points


# Adds a camera-facing ribbon along points to a mesh between surface_begin(PRIMITIVE_TRIANGLES) and surface_end().
# widths are half-widths per point (the glow's edge), alphas fade it per point. UV.y runs 0..1 across for the shader.
static func add_ribbon(target: ImmediateMesh, points: Array[Vector3], widths: PackedFloat32Array,
		alphas: PackedFloat32Array, eye: Vector3) -> void:
	if points.size() < 2:
		return
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in points.size():
		var along := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var across := along.cross(eye - points[i])
		if across.length_squared() < 0.0000001:
			across = along.cross(Vector3.UP)
		across = across.normalized() * widths[i]
		left.append(points[i] - across)
		right.append(points[i] + across)
	for i in points.size() - 1:
		var a0 := Color(1, 1, 1, alphas[i])
		var a1 := Color(1, 1, 1, alphas[i + 1])
		_vertex(target, left[i], 0.0, a0)
		_vertex(target, right[i], 1.0, a0)
		_vertex(target, right[i + 1], 1.0, a1)
		_vertex(target, left[i], 0.0, a0)
		_vertex(target, right[i + 1], 1.0, a1)
		_vertex(target, left[i + 1], 0.0, a1)


static func _vertex(target: ImmediateMesh, at: Vector3, across: float, color: Color) -> void:
	target.surface_set_color(color)
	target.surface_set_uv(Vector2(0.0, across))
	target.surface_add_vertex(at)
