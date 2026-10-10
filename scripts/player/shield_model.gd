extends RefCounted

# The shield model, built in code: a faceted octagonal shield with a raised plate and boss, flat shaded in a few
# steps (PSX style), a small pixel-art texture of grooves and a glyph, a neon rim and a glowing gem in the center.
# build() returns a Node3D whose decorated face points along +Y (the same orientation the old disc had).
# The root carries the meta "mats" = {body, rim, gem}: the materials the shield script recolors for its states.

const SIDES := 8
const RADIUS := 0.26
const TEXTURE_SIZE := 32
const SHADE_STEPS := 3.0
const LIGHT_DIRECTION := Vector3(0.45, 0.8, 0.4)

# (radius as a fraction of RADIUS, height, band color). The shield is built outward-in on the front.
const FRONT_PROFILE := [
	[1.0, 0.0, Color(0.17, 0.2, 0.32)],      # outer edge
	[0.86, 0.022, Color(0.3, 0.36, 0.52)],   # bevel
	[0.58, 0.04, Color(0.2, 0.25, 0.4)],     # main plate
	[0.3, 0.052, Color(0.26, 0.32, 0.5)],    # step up to the boss
	[0.2, 0.09, Color(0.36, 0.44, 0.66)],    # boss wall
	[0.0, 0.1, Color(0.4, 0.5, 0.74)],       # boss top
]
const BACK_Y := -0.035

static var _texture: ImageTexture


static func build() -> Node3D:
	var root := Node3D.new()
	var mats := {}
	root.set_meta("mats", mats)

	var body := MeshInstance3D.new()
	body.mesh = _build_body(mats)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)

	# Neon rim around the outer edge (an 8-sided tube, matching the octagon)
	var rim_material := StandardMaterial3D.new()
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.albedo_color = Color(2.6, 1.9, 0.3)
	mats["rim"] = rim_material
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.022
	torus.outer_radius = RADIUS + 0.022
	torus.rings = SIDES
	torus.ring_segments = 4
	torus.material = rim_material
	var rim := MeshInstance3D.new()
	rim.mesh = torus
	rim.rotation.y = PI / SIDES
	rim.position.y = 0.002
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)

	# Glowing gem on the boss
	var gem_material := StandardMaterial3D.new()
	gem_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gem_material.albedo_color = Color(0.4, 2.0, 2.6)
	mats["gem"] = gem_material
	var gem_mesh := SphereMesh.new()
	gem_mesh.radius = 0.045
	gem_mesh.height = 0.09
	gem_mesh.radial_segments = 4
	gem_mesh.rings = 2
	gem_mesh.material = gem_material
	var gem := MeshInstance3D.new()
	gem.mesh = gem_mesh
	gem.position.y = 0.1
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gem)

	return root


static func _ring_point(radius: float, y: float, side: int) -> Vector3:
	var angle := TAU * (float(side) + 0.5) / SIDES
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


static func _build_body(mats: Dictionary) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Front: bands between consecutive profile rings
	for i in FRONT_PROFILE.size() - 1:
		var outer: Array = FRONT_PROFILE[i]
		var inner: Array = FRONT_PROFILE[i + 1]
		for k in SIDES:
			var a := _ring_point(RADIUS * outer[0], outer[1], k)
			var b := _ring_point(RADIUS * outer[0], outer[1], (k + 1) % SIDES)
			var c := _ring_point(RADIUS * inner[0], inner[1], (k + 1) % SIDES)
			var d := _ring_point(RADIUS * inner[0], inner[1], k)
			var color: Color = inner[2]
			if k % 2 == 0:
				color = color.lightened(0.1)
			_add_quad(tool, a, b, c, d, color, true)

	# Side wall and flat back
	var edge_color: Color = FRONT_PROFILE[0][2]
	var back_color := Color(0.1, 0.12, 0.2)
	for k in SIDES:
		var top_a := _ring_point(RADIUS, 0.0, k)
		var top_b := _ring_point(RADIUS, 0.0, (k + 1) % SIDES)
		var low_a := _ring_point(RADIUS, BACK_Y, k)
		var low_b := _ring_point(RADIUS, BACK_Y, (k + 1) % SIDES)
		_add_quad(tool, low_a, low_b, top_b, top_a, edge_color.darkened(0.15), false)
		_add_triangle(tool, Vector3(0, BACK_Y, 0), low_b, low_a, back_color, false)

	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true     # the band colors are picked as screen colors
	material.albedo_texture = _get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	mats["body"] = material
	return mesh


static func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, textured: bool) -> void:
	_add_triangle(tool, a, b, c, color, textured)
	_add_triangle(tool, a, c, d, color, textured)


# Flat shaded: one brightness for the whole triangle, snapped to a few steps
static func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, textured: bool) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return
	normal = normal.normalized()
	var centroid := (a + b + c) / 3.0
	if normal.dot(centroid - Vector3(0.0, -0.02, 0.0)) < 0.0:
		normal = -normal          # make it point away from the middle of the body
	var lit := clampf(normal.dot(LIGHT_DIRECTION.normalized()) * 0.5 + 0.5, 0.0, 1.0)
	lit = floorf(lit * SHADE_STEPS + 0.5) / SHADE_STEPS
	var shaded := Color(color.r, color.g, color.b, 1.0) * (0.45 + 0.75 * lit)
	shaded.a = 1.0
	for vertex in [a, b, c]:
		tool.set_color(shaded)
		# Planar UVs over the face: the texture covers the whole shield, the back and sides sample its dark corner
		if textured:
			tool.set_uv(Vector2(vertex.x, vertex.z) / (RADIUS * 2.0) + Vector2(0.5, 0.5))
		else:
			tool.set_uv(Vector2(0.02, 0.02))
		tool.add_vertex(vertex)


# 32x32 pixel texture multiplied over the front: grooves following the octagon, a cross glyph and some wear
static func _get_texture() -> ImageTexture:
	if _texture:
		return _texture
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var noise := RandomNumberGenerator.new()
	noise.seed = 4
	var half := TEXTURE_SIZE * 0.5
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half) / half
			# Octagon "distance": the larger of the square distance and the diamond distance
			var octagon := maxf(maxf(absf(p.x), absf(p.y)), (absf(p.x) + absf(p.y)) * 0.7071)
			var value := 1.0
			var groove := absf(fmod(octagon * 5.0, 1.0) - 0.5)
			if groove < 0.07:
				value = 0.62                                   # thin groove lines
			if absf(p.x) < 0.045 or absf(p.y) < 0.045:
				if octagon > 0.28 and octagon < 0.82:
					value = 0.7                                # cross plates
			if noise.randf() < 0.025:
				value *= 0.82                                  # wear
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	# Make the corner the back and sides sample dark and plain
	image.set_pixel(0, 0, Color(0.8, 0.8, 0.8, 1.0))
	_texture = ImageTexture.create_from_image(image)
	return _texture
