extends RefCounted

# Shared PSX-style fire building blocks (flamethrower stream and burning enemies):
# a chunky low-res multi-color sprite, a tint ramp that shifts in steps, and particles
# simulated at a low fixed rate so the motion looks choppy.

const SPRITE_SIZE := 12            # drawn with nearest filtering, so each texel becomes a visible block
const PARTICLE_FPS := 15

static var cached_texture: ImageTexture


# Hot white/yellow core with orange edges, speckled with brighter pixels, like old pre-rendered fire
static func make_texture() -> ImageTexture:
	if cached_texture:
		return cached_texture
	var image := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	var noise := RandomNumberGenerator.new()
	noise.seed = 95
	var palette := [
		[Color(1.0, 1.0, 0.85), Color(1.0, 0.95, 0.55)],     # core
		[Color(1.0, 0.9, 0.3), Color(1.0, 0.75, 0.15)],      # middle
		[Color(1.0, 0.58, 0.1), Color(0.95, 0.4, 0.05)],     # rim
	]
	var half := SPRITE_SIZE * 0.5
	for y in SPRITE_SIZE:
		for x in SPRITE_SIZE:
			var offset := (Vector2(x + 0.5, y + 0.5) - Vector2(half, half)) / half
			var reach := offset.length() + noise.randf_range(-0.18, 0.18)
			if reach > 0.95:
				continue
			var tier := 0 if reach < 0.35 else (1 if reach < 0.65 else 2)
			if noise.randf() < 0.12:
				tier = maxi(tier - 1, 0)      # hot speckle
			var choices: Array = palette[tier]
			image.set_pixel(x, y, choices[noise.randi() % 2])
	cached_texture = ImageTexture.create_from_image(image)
	return cached_texture


# options: amount, lifetime, size, speed (Vector2), damping (Vector2), spread, gravity,
# scale_curve (Array of Vector2), colors (Array of [offset, Color]), texture (or null for a plain square),
# direction (default +Z), box (Vector3 half extents; default is a small sphere), additive, rotate, fade_near
static func make_emitter(options: Dictionary) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = options["amount"]
	particles.lifetime = options["lifetime"]
	particles.local_coords = false
	particles.emitting = false
	particles.fixed_fps = PARTICLE_FPS
	particles.interpolate = false
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 20))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.direction = options.get("direction", Vector3(0, 0, 1))
	process.spread = options["spread"]
	process.initial_velocity_min = options["speed"].x
	process.initial_velocity_max = options["speed"].y
	process.damping_min = options["damping"].x
	process.damping_max = options["damping"].y
	process.gravity = options["gravity"]
	if options.has("box"):
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = options["box"]
	else:
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.03
	if options.get("rotate", false):
		process.angle_min = 0.0
		process.angle_max = 360.0

	var curve := Curve.new()
	for point: Vector2 in options["scale_curve"]:
		curve.add_point(point)
	var curve_texture := CurveTexture.new()
	curve_texture.curve = curve
	process.scale_curve = curve_texture

	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var stops: Array = options["colors"]
	gradient.offsets = PackedFloat32Array(stops.map(func(stop: Array) -> float: return stop[0]))
	gradient.colors = PackedColorArray(stops.map(func(stop: Array) -> Color: return stop[1]))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if options.get("additive", false) else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if options.get("fade_near", false):
		# Sprites right in front of the lens dissolve in a dither instead of filling the screen
		material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		material.distance_fade_min_distance = 0.3
		material.distance_fade_max_distance = 1.0
	if options["texture"]:
		material.albedo_texture = options["texture"]

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * options["size"]
	quad.material = material
	particles.draw_pass_1 = quad
	return particles
