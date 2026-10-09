shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// Dark filled surface with bright wireframe edges. Needs non-indexed triangles whose
// vertex colors are (1,0,0), (0,1,0), (0,0,1) so edges can be found with barycentric coordinates.

uniform vec3 fill_low : source_color = vec3(0.02, 0.0, 0.1);
uniform vec3 fill_high : source_color = vec3(0.12, 0.0, 0.25);
uniform vec3 line_low : source_color = vec3(0.1, 0.3, 1.0);
uniform vec3 line_high : source_color = vec3(1.0, 0.15, 0.85);
uniform vec3 haze_color : source_color = vec3(1.0, 0.45, 0.2);
uniform float height_base = 0.0;
uniform float height_scale = 200.0;
uniform float line_pixels = 1.6;
uniform float haze_distance = 2500.0;

varying vec3 bary;
varying float world_height;

void vertex() {
	bary = COLOR.rgb;
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Per-pixel distance: interpolating per-vertex distances goes wrong on huge triangles
	float view_distance = length(VERTEX);
	float edge = min(min(bary.x, bary.y), bary.z);
	float width = fwidth(edge) * line_pixels;
	float line = 1.0 - step(width, edge);

	float h = clamp((world_height - height_base) / height_scale, 0.0, 1.0);
	vec3 fill = mix(fill_low, fill_high, h);
	vec3 ink = mix(line_low, line_high, h);
	vec3 color = mix(fill, ink, line);

	float haze = clamp(view_distance / haze_distance, 0.0, 1.0);
	color = mix(color, haze_color * 0.6, haze * haze * 0.7);
	ALBEDO = color;
}
