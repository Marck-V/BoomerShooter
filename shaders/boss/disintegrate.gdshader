shader_type spatial;

// Godot Man falling apart: his own texture, eaten away in blocks from the head down. The blocks go in a random order
// (a fixed hash of where each one is, so they do not shimmer), and the ones about to go glow along the edge.
// `progress` runs 0 to 1; y_bottom and y_top are his feet and head in world space.

uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float y_bottom = 0.0;
uniform float y_top = 8.0;
uniform float block_size = 0.35;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float edge_width = 0.1;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float height = clamp((world_pos.y - y_bottom) / max(y_top - y_bottom, 0.001), 0.0, 1.0);
	float random_part = hash(floor(world_pos / block_size));
	// 0 at the head (goes first) to 1 at the feet (goes last), mixed with the random order
	float order = (1.0 - height) * 0.55 + random_part * 0.45;
	float cut = progress * (1.0 + edge_width);
	if (order < cut - edge_width) {
		discard;
	}
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = base.rgb;
	ROUGHNESS = 0.85;
	float glow = 1.0 - clamp((order - (cut - edge_width)) / edge_width, 0.0, 1.0);
	EMISSION = edge_color.rgb * glow * 4.0 * step(0.001, progress);
}
