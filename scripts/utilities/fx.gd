class_name FX

# The pieces most effects build their looks from in code: a round soft glow texture and an unshaded material.


# A round soft glow, `size` pixels across: the gradient runs from the centre (offset 0) to the edge (offset 1)
static func radial_texture(offsets: Array, colors: Array, size := 64) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


# A material lit by nothing, so it shows `color` as it is. `transparent` lets its alpha (or its texture's) show through;
# `additive` adds its light to what is behind it, the usual look for glows, sparks and flashes.
static func unshaded(color := Color.WHITE, transparent := false, additive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	return material
