extends RefCounted

# Glowing blue blood splats left on walls and floors by hit sprays and death bursts.
# Rays from the enemy find nearby surfaces; a Decal is placed there once the blood would
# have reached it. Splat textures are generated in code, and the total count is capped.
# Shapes vary between splashes, directional spatter and fine speckle; floors also get puddles.
# Use: BloodDecals.splatter(tree, point, shot_direction, amount_scale, thickness)
#      BloodDecals.burst(tree, point, amount_scale, thickness)
# `thickness` scales the size of the splats: a big enemy leaves big puddles.

const TEXTURE_SIZE := 96
const SPLASH_VARIANTS := 6
const PUDDLE_VARIANTS := 3
const PUDDLE_CHANCE := 0.35          # how often a splat landing on a floor is a puddle instead
const PUDDLE_SIZE_SCALE := 1.6
const FLOOR_MIN_NORMAL_Y := 0.7      # surfaces flatter than this count as floor
const MAX_DECALS := 36
const HOLD_TIME := 10.0
const FADE_TIME := 3.0
const BLOOD_SPEED := 8.0             # how fast the blood travels, for the placement delay
const BLOOD_COLOR := Color(0.3, 0.7, 1.0)  # colour of the splat texture, which is also its emission colour
const EMISSION_ENERGY := 2.5         # how brightly the splats glow (the glow effect makes them shine)

static var _textures: Array[ImageTexture] = []  # the splashes, then the puddles
static var _emission_textures: Array[ImageTexture] = []  # same shapes, glow colour only where the splat is
static var _active: Array[Decal] = []


# A normal hit: a splat on the surface behind the enemy and sometimes one on the floor
static func splatter(tree: SceneTree, point: Vector3, direction: Vector3, amount_scale := 1.0, thickness := 1.0) -> void:
	var dir := direction.normalized()

	if randf() < minf(amount_scale * 1.2, 1.0):
		var wall_dir := (dir + _random_unit() * 0.35).normalized()
		_cast_splat(tree, point, wall_dir, 6.0, randf_range(0.3, 0.6) * thickness)

	if randf() < amount_scale * 0.7:
		var floor_dir := (Vector3.DOWN + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)) + dir * 0.4).normalized()
		_cast_splat(tree, point, floor_dir, 4.0, randf_range(0.3, 0.6) * thickness)


# Death: a big spatter in every direction, mostly across the floor and nearby walls
static func burst(tree: SceneTree, point: Vector3, amount_scale := 1.0, thickness := 1.0) -> void:
	var count := maxi(int(9 * amount_scale * sqrt(thickness)), 3)
	for i in count:
		var angle := randf() * TAU
		var dir: Vector3
		if i % 3 == 0:
			dir = (Vector3.DOWN + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.2, 0.7)).normalized()
		else:
			dir = Vector3(cos(angle), randf_range(-0.5, 0.1), sin(angle)).normalized()
		_cast_splat(tree, point, dir, 5.0 * sqrt(thickness), randf_range(0.55, 1.1) * thickness)

	# The body always leaves a pool underneath it
	_cast_splat(tree, point, Vector3.DOWN, 5.0 * sqrt(thickness), randf_range(0.8, 1.1) * thickness, true)


static func _cast_splat(tree: SceneTree, from: Vector3, dir: Vector3, length: float, splat_size: float, force_puddle := false) -> void:
	var hit := PhysicsLayers.surface_ray(tree, from, from + dir * length)
	if hit.is_empty():
		return

	var hit_position: Vector3 = hit["position"]
	var delay := from.distance_to(hit_position) / BLOOD_SPEED
	tree.create_timer(delay, false).timeout.connect(_place_decal.bind(tree, hit_position, hit["normal"], splat_size, force_puddle))


static func _place_decal(tree: SceneTree, position: Vector3, normal: Vector3, splat_size: float, force_puddle := false) -> void:
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	if parent == null or not parent.is_inside_tree():
		return

	# Recycle the oldest splats once at the cap
	_active = _active.filter(func(d): return is_instance_valid(d))
	while _active.size() >= MAX_DECALS:
		var oldest: Decal = _active.pop_front()
		oldest.queue_free()

	var textures := _get_textures()
	var is_puddle := normal.normalized().y >= FLOOR_MIN_NORMAL_Y and (force_puddle or randf() < PUDDLE_CHANCE)
	var variant := randi_range(SPLASH_VARIANTS, textures.size() - 1) if is_puddle else randi_range(0, SPLASH_VARIANTS - 1)
	var width := splat_size * (PUDDLE_SIZE_SCALE if is_puddle else 1.0)
	var decal := Decal.new()
	decal.texture_albedo = textures[variant]
	# Stretched a little differently on each axis so the same texture doesn't repeat exactly
	decal.size = Vector3(width * randf_range(0.8, 1.25), maxf(0.6, splat_size * 0.5), width * randf_range(0.8, 1.25))
	decal.texture_emission = _emission_textures[variant]
	decal.emission_energy = EMISSION_ENERGY
	decal.modulate = Color(1.0, 1.0, 1.0, 1.0)  # only used for the fade-out
	decal.cull_mask = 1
	parent.add_child(decal)

	# Decals project along their local -Y, so +Y points out of the surface; spin randomly around it
	var up := normal.normalized()
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := reference.cross(up).normalized()
	var facing := Basis(x, up, x.cross(up)).rotated(up, randf() * TAU)
	decal.global_transform = Transform3D(facing, position + up * 0.02)

	_active.append(decal)
	var tween := decal.create_tween()
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(decal, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_property(decal, "emission_energy", 0.0, FADE_TIME)
	tween.tween_callback(decal.queue_free)


static func _random_unit() -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))


static func _get_textures() -> Array[ImageTexture]:
	if _textures.is_empty():
		for i in SPLASH_VARIANTS + PUDDLE_VARIANTS:
			var image := _make_splash_image(i) if i < SPLASH_VARIANTS else _make_puddle_image(i)
			_textures.append(ImageTexture.create_from_image(image))
			_emission_textures.append(ImageTexture.create_from_image(_make_emission_image(image)))
	return _textures


static func _new_image() -> Image:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(BLOOD_COLOR, 0.0))
	return image


static func _new_rng(variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 13
	return rng


# Cycles through three looks: a splash, directional spatter and fine speckle
static func _make_splash_image(variant: int) -> Image:
	var rng := _new_rng(variant)
	var image := _new_image()
	var center := Vector2(TEXTURE_SIZE, TEXTURE_SIZE) * 0.5

	match variant % 3:
		0: # A lumpy main blob with droplets flung outward from it
			_draw_blob(image, center, rng.randf_range(12.0, 19.0), rng, 0.35)
			for i in rng.randi_range(8, 14):
				var angle := rng.randf() * TAU
				var distance := rng.randf_range(20.0, 38.0)
				_draw_blob(image, center + Vector2.from_angle(angle) * distance, rng.randf_range(1.2, 4.5), rng, 0.25, rng.randf_range(1.0, 2.0), angle)
		1: # Blood that hit at an angle: a small blob, then teardrops fanning out one way and thinning
			var heading := rng.randf() * TAU
			var origin := center - Vector2.from_angle(heading) * 14.0
			_draw_blob(image, origin, rng.randf_range(7.0, 11.0), rng, 0.3, 1.4, heading)
			for i in rng.randi_range(12, 18):
				var angle := heading + rng.randf_range(-0.6, 0.6)
				var reach := rng.randf_range(0.2, 1.0)
				var radius := lerpf(4.0, 1.0, reach) * rng.randf_range(0.7, 1.2)
				_draw_blob(image, origin + Vector2.from_angle(angle) * lerpf(8.0, 44.0, reach), radius, rng, 0.2, rng.randf_range(1.3, 2.6), angle)
		2: # A fine scatter of specks, denser toward the middle, around a few small blobs
			for i in rng.randi_range(2, 4):
				var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 14.0)
				_draw_blob(image, center + offset, rng.randf_range(3.0, 7.0), rng, 0.35)
			for i in rng.randi_range(30, 45):
				var distance := pow(rng.randf(), 0.7) * 42.0
				_draw_blob(image, center + Vector2.from_angle(rng.randf() * TAU) * distance, rng.randf_range(0.8, 2.2), rng, 0.2)

	return image


# Overlapping lobes merge into one pool, with a few drips beside it and a darker, deeper middle
static func _make_puddle_image(variant: int) -> Image:
	var rng := _new_rng(variant)
	var image := _new_image()
	var center := Vector2(TEXTURE_SIZE, TEXTURE_SIZE) * 0.5

	_draw_blob(image, center, rng.randf_range(16.0, 21.0), rng, 0.3)
	for i in rng.randi_range(4, 7):
		var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 21.0)
		_draw_blob(image, center + offset, rng.randf_range(7.0, 13.0), rng, 0.3)
	for i in rng.randi_range(3, 7):
		var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(36.0, 44.0)
		_draw_blob(image, center + offset, rng.randf_range(1.0, 2.5), rng, 0.2)

	_shade_depth(image)
	return image


# Darkens pixels by how far they are from the edge, leaving a bright rim around the pool
static func _shade_depth(image: Image) -> void:
	var source := image.duplicate() as Image
	var samples := 8
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var inside := 0.0
			for ring: float in [3.0, 6.0]:
				for i in samples:
					var sample := Vector2(x, y) + Vector2.from_angle(TAU * i / samples) * ring
					var sx := int(sample.x)
					var sy := int(sample.y)
					if sx >= 0 and sy >= 0 and sx < TEXTURE_SIZE and sy < TEXTURE_SIZE:
						inside += source.get_pixel(sx, sy).a
			var depth := inside / (samples * 2.0)
			var shade := lerpf(1.0, 0.45, depth * depth)
			image.set_pixel(x, y, Color(pixel.r * shade, pixel.g * shade, pixel.b * shade, pixel.a))


# Decal emission ignores alpha, so the splat shape is baked in: glow colour where the blood is, black elsewhere
static func _make_emission_image(splat: Image) -> Image:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var pixel := splat.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * pixel.a, pixel.g * pixel.a, pixel.b * pixel.a, 1.0))
	return image


# `roughness` makes the edge lumpy (0 is a circle); `stretch` elongates the blob along `rotation`
static func _draw_blob(image: Image, center: Vector2, radius: float, rng: RandomNumberGenerator, roughness: float, stretch := 1.0, rotation := 0.0) -> void:
	var lobes: Array[Vector3] = []  # x: lobes around the edge, y: how far they stick out, z: phase
	var total_bulge := 0.0
	for lobe_count: float in [2.0, 3.0, 5.0, 8.0]:
		var bulge := roughness * rng.randf_range(0.3, 1.0) / sqrt(lobe_count)
		lobes.append(Vector3(lobe_count, bulge, rng.randf() * TAU))
		total_bulge += bulge

	var reach := radius * stretch * (1.0 + total_bulge) + 1.0
	var min_x := maxi(int(center.x - reach), 0)
	var max_x := mini(int(center.x + reach) + 1, TEXTURE_SIZE - 1)
	var min_y := maxi(int(center.y - reach), 0)
	var max_y := mini(int(center.y + reach) + 1, TEXTURE_SIZE - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var offset := (Vector2(x + 0.5, y + 0.5) - center).rotated(-rotation)
			offset.x /= stretch
			var edge := 1.0
			var angle := offset.angle()
			for lobe in lobes:
				edge += lobe.y * sin(lobe.x * angle + lobe.z)
			edge *= radius
			var alpha := 1.0 - smoothstep(edge - 1.2, edge, offset.length())
			var existing := image.get_pixel(x, y)
			if alpha > existing.a:
				image.set_pixel(x, y, Color(existing.r, existing.g, existing.b, alpha))
