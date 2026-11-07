extends StaticBody3D
class_name DestructibleWindow

# A window pane that cracks when it is hit and shatters into shards when it takes enough, or when a blast reaches it.
# A TrenchBroom brush entity ("window"): draw a thin brush (any texture, it is covered with the glass shader) and
# the pane is its shape. Also works in a plain scene: a StaticBody3D with this script, a MeshInstance3D and a
# CollisionShape3D. Once broken the opening is clear for the player to walk through.
#
# Anything that hits a body with a damage() method breaks it, so bullets, the thrown shield and energy balls all do.

const GLASS_SHADER := preload("res://shaders/environment/window_glass.gdshader")
const BREAK_SOUND := "assets/audio/sfx/impacts/glass_breaking.mp3"
const CRACK_SOUND := "assets/audio/sfx/impacts/bullet_hit_metal.mp3"

const SHARD_TARGET := 26             # roughly how many shards a pane breaks into (cells follow the pane's size)
const MIN_CELL := 0.4                # shards never get smaller than this, in metres
const SHARD_THICKNESS := 0.03
const SHARD_SPEED := 4.5             # how hard the impact throws the shards
const SHARD_SPREAD := 2.2
const SHARD_ALPHA := 0.42

@export var health := 20.0           # a pistol shot does 25, so the default breaks with one hit
@export var tint := Color(0.3, 0.55, 0.65)
@export var crack_first := true      # a hit that does not break the pane cracks it; false: it shatters or stays clear

var max_health := 0.0
var broken := false
var glass: ShaderMaterial
var shard_material: ShaderMaterial
var meshes: Array[MeshInstance3D] = []
var bounds := AABB()                 # in this node's space
var axis_u := Vector3.RIGHT          # local unit axes of the pane: across, up the face, and its thin direction
var axis_v := Vector3.UP
var axis_n := Vector3.BACK
var size_u := 1.0
var size_v := 1.0


func _ready() -> void:
	add_to_group("Blastable")
	max_health = health
	# The map build adds the brush's meshes and sets the entity's properties right after it is added
	_setup.call_deferred()


func _setup() -> void:
	_find_meshes(self)
	if meshes.is_empty():
		return
	bounds = _local_bounds()
	_work_out_axes()

	glass = ShaderMaterial.new()
	glass.shader = GLASS_SHADER
	glass.set_shader_parameter("tint", tint)
	glass.set_shader_parameter("damage", 0.0)
	glass.set_shader_parameter("shatter_flash", 0.0)
	shard_material = glass.duplicate()
	shard_material.set_shader_parameter("base_alpha", SHARD_ALPHA)
	for mesh in meshes:
		mesh.material_override = glass
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _find_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		_find_meshes(child)


func _local_bounds() -> AABB:
	var box := AABB()
	var first := true
	for mesh in meshes:
		var relative := global_transform.affine_inverse() * mesh.global_transform
		var part := relative * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


# The thinnest side of the brush is the glass's thickness; of the other two, the wider one runs across the pane
# (the taller one when it is a wall, so cracks and glints follow the vertical)
func _work_out_axes() -> void:
	var s := bounds.size
	var thin := 0
	if s.y < s[thin]:
		thin = 1
	if s.z < s[thin]:
		thin = 2
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	axis_n = axes[thin]
	var others: Array[int] = []
	for i in 3:
		if i != thin:
			others.append(i)
	if thin == 1:                                            # a skylight or floor pane: width is the longer side
		others.sort_custom(func(a, b): return s[a] > s[b])
	else:                                                    # a wall pane: up is the world's up
		others.sort_custom(func(a, b): return a != 1 and b == 1)
	axis_u = axes[others[0]]
	axis_v = axes[others[1]]
	size_u = s[others[0]]
	size_v = s[others[1]]


# ---------------------------
# Damage
# ---------------------------
func damage(amount: float, _multiplier: float = 1.0) -> void:
	if broken or glass == null:
		return
	health -= amount
	var impact := _impact_point()
	if health <= 0.0:
		shatter(impact, _push_direction())
		return
	if crack_first:
		_crack(impact)


# A blast within reach shatters the pane, from the side it came from
func on_blast(center: Vector3, radius: float) -> void:
	if broken or glass == null:
		return
	var nearest := _closest_point(center)
	if nearest.distance_to(center) <= radius:
		shatter(nearest, (nearest - center).normalized())


func _crack(impact: Vector3) -> void:
	var fraction := clampf(1.0 - health / max_health, 0.1, 0.95)
	glass.set_shader_parameter("damage", maxf(fraction, glass.get_shader_parameter("damage")))
	glass.set_shader_parameter("impact_point", impact)
	glass.set_shader_parameter("pane_right", global_basis * axis_u)
	glass.set_shader_parameter("pane_up", global_basis * axis_v)
	glass.set_shader_parameter("shatter_flash", 0.6)
	create_tween().tween_property(glass, "shader_parameter/shatter_flash", 0.0, 0.18)
	Audio.play_at(impact, CRACK_SOUND)


func shatter(impact: Vector3, push: Vector3) -> void:
	if broken:
		return
	broken = true
	remove_from_group("Blastable")
	collision_layer = 0
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	for mesh in meshes:
		mesh.visible = false
	_spawn_shards(impact, push)
	Audio.play_at(impact, BREAK_SOUND)
	var player = GlobalVariables.player
	if is_instance_valid(player) and player.has_method("add_camera_shake") and player.global_position.distance_to(impact) < 10.0:
		player.add_camera_shake(0.12)
	get_tree().create_timer(Debris.LIFETIME + Debris.SHRINK_TIME + 1.0, false).timeout.connect(queue_free)


# ---------------------------
# Shards
# ---------------------------
# The pane is cut into a jittered grid and each cell into two triangles. One unit prism, stretched into each
# triangle by its own transform, serves for all of them.
func _spawn_shards(impact: Vector3, push: Vector3) -> void:
	var cell := maxf(MIN_CELL, sqrt(size_u * size_v / float(SHARD_TARGET) * 2.0))
	var nu := clampi(roundi(size_u / cell), 1, 12)
	var nv := clampi(roundi(size_v / cell), 1, 12)
	var centre := bounds.get_center()

	var basis_world := Basis(global_basis * axis_u, global_basis * axis_v, global_basis * axis_n).orthonormalized()
	var points: Array = []                                   # (nu+1) x (nv+1) corner points, as 2D pane coordinates
	for j in nv + 1:
		var row: Array[Vector2] = []
		for i in nu + 1:
			var p := Vector2((float(i) / nu - 0.5) * size_u, (float(j) / nv - 0.5) * size_v)
			if i > 0 and i < nu:
				p.x += randf_range(-0.3, 0.3) * size_u / nu
			if j > 0 and j < nv:
				p.y += randf_range(-0.3, 0.3) * size_v / nv
			row.append(p)
		points.append(row)

	var origin := global_transform * centre
	var impact_2d := Vector2(basis_world.x.dot(impact - origin), basis_world.y.dot(impact - origin))
	var mesh := _unit_prism()
	var forward := basis_world.z * signf(basis_world.z.dot(push) if absf(basis_world.z.dot(push)) > 0.05 else 1.0)

	for j in nv:
		for i in nu:
			var a: Vector2 = points[j][i]
			var b: Vector2 = points[j][i + 1]
			var c: Vector2 = points[j + 1][i + 1]
			var d: Vector2 = points[j + 1][i]
			var triangles := [[a, b, c], [a, c, d]] if randf() < 0.5 else [[a, b, d], [b, c, d]]
			for t in triangles:
				_spawn_shard(mesh, basis_world, origin, t[0], t[1], t[2], impact_2d, forward)


func _spawn_shard(mesh: Mesh, basis_world: Basis, origin: Vector3, p0: Vector2, p1: Vector2, p2: Vector2, impact_2d: Vector2, forward: Vector3) -> void:
	var centroid := (p0 + p1 + p2) / 3.0
	var e1 := p1 - p0
	var e2 := p2 - p0
	# The prism spans (0,0)-(1,0)-(0,1); this maps it onto the triangle around its own centroid
	var skew := Basis(Vector3(e1.x, e1.y, 0.0), Vector3(e2.x, e2.y, 0.0), Vector3(0.0, 0.0, SHARD_THICKNESS))
	var offset := skew * Vector3(-1.0 / 3.0, -1.0 / 3.0, 0.0)
	var at := origin + basis_world.x * centroid.x + basis_world.y * centroid.y

	var away := centroid - impact_2d
	var closeness := 1.0 / (1.0 + away.length() * 1.6)       # shards near the hit fly hardest
	var outward := (basis_world.x * away.x + basis_world.y * away.y).normalized()
	var velocity := forward * SHARD_SPEED * (0.35 + closeness) + outward * SHARD_SPREAD * (0.4 + closeness) + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 1.2), randf_range(-0.5, 0.5))
	var spin := Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	var span := maxf(maxf(e1.length(), e2.length()), 0.1)
	Debris.spawn(get_tree(), mesh, shard_material, Transform3D(skew, offset), at, basis_world, velocity, spin, Vector3(span * 0.6, span * 0.6, SHARD_THICKNESS * 2.0))


static var prism_mesh: ArrayMesh

# A triangle (0,0) (1,0) (0,1) with some thickness: front, back and three sides
static func _unit_prism() -> ArrayMesh:
	if prism_mesh != null:
		return prism_mesh
	var front: Array[Vector3] = [Vector3(0, 0, 0.5), Vector3(1, 0, 0.5), Vector3(0, 1, 0.5)]
	var back: Array[Vector3] = [Vector3(0, 0, -0.5), Vector3(0, 1, -0.5), Vector3(1, 0, -0.5)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in front + back:
		tool.add_vertex(v)
	for i in 3:                                              # the sides
		var f0 := front[i]
		var f1 := front[(i + 1) % 3]
		var b0 := Vector3(f0.x, f0.y, -0.5)
		var b1 := Vector3(f1.x, f1.y, -0.5)
		for v in [f0, b0, f1, f1, b0, b1]:
			tool.add_vertex(v)
	tool.generate_normals()
	prism_mesh = tool.commit()
	return prism_mesh


# ---------------------------
# Geometry helpers
# ---------------------------
# Where a shot that just landed hit the pane: the player's view ray against the pane's plane
func _impact_point() -> Vector3:
	var centre := global_transform * bounds.get_center()
	var normal: Vector3 = (global_basis * axis_n).normalized()
	var player = GlobalVariables.player
	var camera: Camera3D = player.get("camera") if is_instance_valid(player) else null
	if camera == null:
		return centre
	var ray := -camera.global_basis.z
	var facing := ray.dot(normal)
	if absf(facing) < 0.01:
		return centre
	var along := (centre - camera.global_position).dot(normal) / facing
	if along <= 0.0:
		return centre
	return _closest_point(camera.global_position + ray * along)


func _push_direction() -> Vector3:
	var player = GlobalVariables.player
	var camera: Camera3D = player.get("camera") if is_instance_valid(player) else null
	if camera == null:
		return (global_basis * axis_n).normalized()
	return -camera.global_basis.z


# The point of the pane nearest `point` (clamped inside its bounds)
func _closest_point(point: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * point
	var low := bounds.position
	var high := bounds.end
	local = Vector3(clampf(local.x, low.x, high.x), clampf(local.y, low.y, high.y), clampf(local.z, low.z, high.z))
	return global_transform * local
