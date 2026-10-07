extends RefCounted

# Blood splats left on walls and floors by hit sprays and death bursts.
# Rays from the enemy find nearby surfaces; a Decal is placed there once the blood would
# have reached it. Splat textures are generated in code, and the total count is capped.
# Use: BloodDecals.splatter(tree, point, shot_direction, amount_scale)
#      BloodDecals.burst(tree, point, amount_scale)

const ENVIRONMENT_MASK := 2          # physics layer 2 ("Environment")
const TEXTURE_SIZE := 64
const TEXTURE_VARIANTS := 4
const MAX_DECALS := 36
const HOLD_TIME := 10.0
const FADE_TIME := 3.0
const BLOOD_SPEED := 8.0             # how fast the blood travels, for the placement delay

static var _textures: Array[ImageTexture] = []
static var _active: Array[Decal] = []


# A normal hit: a splat on the surface behind the enemy and sometimes one on the floor
static func splatter(tree: SceneTree, point: Vector3, direction: Vector3, amount_scale := 1.0) -> void:
	var dir := direction.normalized()

	if randf() < minf(amount_scale * 1.2, 1.0):
		var wall_dir := (dir + _random_unit() * 0.35).normalized()
		_cast_splat(tree, point, wall_dir, 6.0, randf_range(0.3, 0.6))

	if randf() < amount_scale * 0.7:
		var floor_dir := (Vector3.DOWN + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)) + dir * 0.4).normalized()
		_cast_splat(tree, point, floor_dir, 4.0, randf_range(0.3, 0.6))


# Death: a big spatter in every direction, mostly across the floor and nearby walls
static func burst(tree: SceneTree, point: Vector3, amount_scale := 1.0) -> void:
	var count := maxi(int(9 * amount_scale), 3)
	for i in count:
		var angle := randf() * TAU
		var dir: Vector3
		if i % 3 == 0:
			dir = (Vector3.DOWN + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.2, 0.7)).normalized()
		else:
			dir = Vector3(cos(angle), randf_range(-0.5, 0.1), sin(angle)).normalized()
		_cast_splat(tree, point, dir, 5.0, randf_range(0.55, 1.1))


static func _cast_splat(tree: SceneTree, from: Vector3, dir: Vector3, length: float, splat_size: float) -> void:
	var world := tree.root.world_3d
	if world == null:
		return

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	query.collision_mask = ENVIRONMENT_MASK
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var hit_position: Vector3 = hit["position"]
	var delay := from.distance_to(hit_position) / BLOOD_SPEED
	tree.create_timer(delay).timeout.connect(_place_decal.bind(tree, hit_position, hit["normal"], splat_size))


static func _place_decal(tree: SceneTree, position: Vector3, normal: Vector3, splat_size: float) -> void:
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	if parent == null or not parent.is_inside_tree():
		return

	# Recycle the oldest splats once at the cap
	_active = _active.filter(func(d): return is_instance_valid(d))
	while _active.size() >= MAX_DECALS:
		var oldest: Decal = _active.pop_front()
		oldest.queue_free()

	var textures := _get_textures()
	var decal := Decal.new()
	decal.texture_albedo = textures[randi() % textures.size()]
	decal.size = Vector3(splat_size, 0.6, splat_size)
	decal.modulate = Color(1.0, 0.1, 0.12, 1.0)
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
	tween.tween_callback(decal.queue_free)


static func _random_unit() -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))


static func _get_textures() -> Array[ImageTexture]:
	if _textures.is_empty():
		for i in TEXTURE_VARIANTS:
			_textures.append(_make_splat_texture(i * 7919 + 13))
	return _textures


# A main blob, scattered satellite droplets and a couple of droplet trails
static func _make_splat_texture(seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.03, 0.06, 0.0))
	var center := Vector2(TEXTURE_SIZE, TEXTURE_SIZE) * 0.5

	_draw_blob(image, center + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), rng.randf_range(9.0, 13.0))

	for i in rng.randi_range(8, 14):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(13.0, 28.0)
		_draw_blob(image, center + Vector2(cos(angle), sin(angle)) * distance, rng.randf_range(1.3, 4.2))

	for i in rng.randi_range(1, 2):
		var angle := rng.randf() * TAU
		var trail := Vector2(cos(angle), sin(angle))
		for k in 9:
			var blob_radius := lerpf(4.0, 1.0, float(k) / 8.0)
			_draw_blob(image, center + trail * (10.0 + k * 2.8), blob_radius)

	return ImageTexture.create_from_image(image)


static func _draw_blob(image: Image, center: Vector2, radius: float) -> void:
	var min_x := maxi(int(center.x - radius) - 1, 0)
	var max_x := mini(int(center.x + radius) + 1, TEXTURE_SIZE - 1)
	var min_y := maxi(int(center.y - radius) - 1, 0)
	var max_y := mini(int(center.y + radius) + 1, TEXTURE_SIZE - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := 1.0 - smoothstep(radius * 0.65, radius, distance)
			var existing := image.get_pixel(x, y)
			if alpha > existing.a:
				image.set_pixel(x, y, Color(existing.r, existing.g, existing.b, alpha))
