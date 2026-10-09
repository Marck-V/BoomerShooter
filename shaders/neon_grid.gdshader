shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// Endless neon grid floor in world space that melts into the horizon glow.

uniform float cell_size = 16.0;
uniform float line_pixels = 1.4;
uniform vec3 fill_near : source_color = vec3(0.03, 0.0, 0.12);
uniform vec3 fill_far : source_color = vec3(0.35, 0.05, 0.4);
uniform vec3 line_near : source_color = vec3(0.1, 0.35, 1.0);
uniform vec3 line_far : source_color = vec3(1.0, 0.2, 0.9);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.45, 0.2);
uniform float fade_distance = 3400.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Per-pixel distance: interpolating per-vertex distances goes wrong on huge triangles
	float view_distance = length(VERTEX);
	vec2 coord = world_position.xz / cell_size;
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
	float line = 1.0 - min(min(grid.x, grid.y) / line_pixels, 1.0);

	float t = clamp(view_distance / fade_distance, 0.0, 1.0);
	vec3 fill = mix(fill_near, fill_far, t * t);
	vec3 ink = mix(line_near, line_far, sqrt(t));
	vec3 color = mix(fill, ink, line);
	color = mix(color, horizon_color, pow(t, 5.0));
	ALBEDO = color;
}
