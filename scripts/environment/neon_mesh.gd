extends RefCounted

# Shared helpers for the neon wireframe scenery (see shaders/neon_wire.gdshader).

const NEON_WIRE: Shader = preload("res://shaders/neon_wire.gdshader")


# Triangle whose vertex colors carry barycentric coordinates for the wireframe shader
static func add_wire_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var corners := [a, b, c]
	var colors := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	for i in 3:
		tool.set_color(colors[i])
		tool.add_vertex(corners[i])


static func wire_material(fill_low: Color, fill_high: Color, line_low: Color, line_high: Color, base: float, height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = NEON_WIRE
	material.set_shader_parameter("fill_low", fill_low)
	material.set_shader_parameter("fill_high", fill_high)
	material.set_shader_parameter("line_low", line_low)
	material.set_shader_parameter("line_high", line_high)
	material.set_shader_parameter("height_base", base)
	material.set_shader_parameter("height_scale", height)
	return material
