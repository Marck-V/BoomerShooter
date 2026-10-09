shader_type spatial;
render_mode unshaded, fog_disabled;

// Banded retro planet: hard color stripes and a three-step lit side.

uniform vec3 color_a : source_color = vec3(1.0, 0.55, 0.75);
uniform vec3 color_b : source_color = vec3(0.4, 0.12, 0.85);
uniform vec3 light_direction = vec3(-0.6, 0.3, 0.7);
uniform float stripes = 9.0;

varying vec3 object_normal;

void vertex() {
	object_normal = normalize(NORMAL);
}

void fragment() {
	float band = floor((object_normal.y * 0.5 + 0.5) * stripes) / stripes;
	vec3 color = mix(color_b, color_a, fract(band * 2.0 + 0.2));
	float lit = dot(object_normal, normalize(light_direction)) * 0.5 + 0.5;
	lit = floor(lit * 3.0) / 3.0;
	ALBEDO = color * mix(0.3, 1.15, lit);
}
