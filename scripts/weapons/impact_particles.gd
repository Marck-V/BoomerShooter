extends Node3D

# Sparks + smoke burst spawned where a bullet hits. Built in code so there is no scene to maintain.
# Use: ImpactParticles.spawn(get_tree(), hit_point, hit_normal, amount_scale)

const SPARK_COUNT := 14
const SMOKE_COUNT := 7
const CLEANUP_TIME := 1.6

static var _spark_mesh: QuadMesh
static var _smoke_mesh: QuadMesh


static func spawn(tree: SceneTree, point: Vector3, normal: Vector3, amount_scale := 1.0) -> void:
	var effect: Node3D = new()
	tree.root.add_child(effect)
	effect._start(point, normal, amount_scale)


func _start(point: Vector3, normal: Vector3, amount_scale: float) -> void:
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	global_basis = Basis(x, up, x.cross(up))
	global_position = point + up * 0.03

	_add_sparks(maxi(int(SPARK_COUNT * amount_scale), 3))
	_add_smoke(maxi(int(SMOKE_COUNT * amount_scale), 2))
	get_tree().create_timer(CLEANUP_TIME).timeout.connect(queue_free)


func _add_sparks(count: int) -> void:
	if _spark_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(2.5, 1.8, 0.9)
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.03, 0.03)
		_spark_mesh.material = material

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.7, 1.0),
		Color(1.0, 0.55, 0.15, 0.9),
		Color(1.0, 0.25, 0.0, 0.0),
	])

	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = count
	sparks.lifetime = 0.4
	sparks.mesh = _spark_mesh
	sparks.direction = Vector3.UP
	sparks.spread = 60.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 6.5
	sparks.gravity = Vector3(0.0, -9.8, 0.0)
	sparks.damping_min = 1.0
	sparks.damping_max = 3.0
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.2
	sparks.color_ramp = gradient
	add_child(sparks)
	sparks.emitting = true


func _add_smoke(count: int) -> void:
	if _smoke_mesh == null:
		var puff := Gradient.new()
		puff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		puff.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.45),
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
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(0.3, 0.3)
		_smoke_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([
		Color(0.62, 0.62, 0.66, 0.55),
		Color(0.32, 0.32, 0.36, 0.0),
	])

	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(1.0, 1.6))

	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.amount = count
	smoke.lifetime = 0.8
	smoke.mesh = _smoke_mesh
	smoke.direction = Vector3.UP
	smoke.spread = 35.0
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 1.2
	smoke.gravity = Vector3(0.0, 0.7, 0.0)
	smoke.damping_min = 0.6
	smoke.damping_max = 1.2
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.1
	smoke.scale_amount_curve = growth
	smoke.color_ramp = fade
	add_child(smoke)
	smoke.emitting = true
