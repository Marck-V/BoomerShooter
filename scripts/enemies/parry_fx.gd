extends RefCounted

# The effects that mean "you can parry this", shared by projectiles and melee fists: soft motes of light and the
# four-point star glint that fires the moment a parry would land.

const MOTE_SIZE := 0.2
const MOTE_BRIGHTNESS := 1.8
const GLINT_TEXTURE_SIZE := 64
const GLINT_GROW_TIME := 0.05
const GLINT_FADE_TIME := 0.22

static var mote_mesh: QuadMesh
static var ember_process: ParticleProcessMaterial
static var wisp_process: ParticleProcessMaterial
static var glint_texture: ImageTexture


# Sparks that hang in the air behind a moving projectile
static func make_embers(emission_radius: float) -> GPUParticles3D:
	if ember_process == null:
		ember_process = _make_mote_process(emission_radius, Vector2(0.2, 0.8), Vector3(0, -1.0, 0))
	return _make_motes(12, 0.5, ember_process)


# Licks of light streaming upwards off a fist. Left behind in the world, so a swing draws them out through the air.
static func make_wisps(emission_radius: float) -> GPUParticles3D:
	if wisp_process == null:
		wisp_process = _make_mote_process(emission_radius, Vector2(0.3, 1.0), Vector3(0, 2.5, 0))
	return _make_motes(14, 0.55, wisp_process)


static func _make_motes(amount: int, lifetime: float, process: ParticleProcessMaterial) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.process_material = process
	particles.draw_pass_1 = _get_mote_mesh()
	return particles


static func _get_mote_mesh() -> QuadMesh:
	if mote_mesh != null:
		return mote_mesh
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	glow.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = glow
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color(MOTE_BRIGHTNESS, MOTE_BRIGHTNESS, MOTE_BRIGHTNESS)
	material.disable_fog = true
	mote_mesh = QuadMesh.new()
	mote_mesh.size = Vector2.ONE * MOTE_SIZE
	mote_mesh.material = material
	return mote_mesh


# Motes shrink and cool from yellow to orange as they die
static func _make_mote_process(emission_radius: float, speed: Vector2, gravity: Vector3) -> ParticleProcessMaterial:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 0.9, 0.35, 1.0), Color(1.0, 0.6, 0.1, 0.8), Color(1.0, 0.3, 0.0, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.3))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = emission_radius
	process.spread = 180.0
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = gravity
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.scale_curve = shrink_texture
	process.color_ramp = ramp
	return process


# A sharp star that snaps open on parent and fades. Drawn over everything, or the thing it marks would hide its middle.
static func play_star_glint(parent: Node3D, size: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.disable_fog = true
	material.albedo_texture = _get_glint_texture()
	material.albedo_color = Color(2.6, 2.2, 1.0)
	var quad := QuadMesh.new()
	quad.material = material
	var glint := MeshInstance3D.new()
	glint.mesh = quad
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glint.scale = Vector3.ONE * size * 0.2
	parent.add_child(glint)
	var tween := glint.create_tween()
	tween.tween_property(glint, "scale", Vector3.ONE * size, GLINT_GROW_TIME)
	tween.tween_property(material, "albedo_color:a", 0.0, GLINT_FADE_TIME)
	tween.parallel().tween_property(glint, "scale", Vector3.ONE * size * 0.5, GLINT_FADE_TIME)
	tween.tween_callback(glint.queue_free)


static func _get_glint_texture() -> ImageTexture:
	if glint_texture != null:
		return glint_texture
	var image := Image.create(GLINT_TEXTURE_SIZE, GLINT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in GLINT_TEXTURE_SIZE:
		for x in GLINT_TEXTURE_SIZE:
			var offset := (Vector2(x + 0.5, y + 0.5) / GLINT_TEXTURE_SIZE) * 2.0 - Vector2.ONE
			var across := absf(offset.x)
			var down := absf(offset.y)
			# Two thin spikes crossing at the centre, tapering to nothing at the edges, on a small round glow
			var spikes := exp(-down * 28.0) * maxf(1.0 - across, 0.0) + exp(-across * 28.0) * maxf(1.0 - down, 0.0)
			var centre := exp(-offset.length_squared() * 30.0)
			image.set_pixel(x, y, Color(1, 1, 1, clampf(spikes + centre, 0.0, 1.0)))
	glint_texture = ImageTexture.create_from_image(image)
	return glint_texture
