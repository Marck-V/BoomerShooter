shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D src_tex : source_color, filter_linear, repeat_disable;
uniform vec2 centroid = vec2(0.5);
uniform vec2 src_centroid = vec2(0.5);
uniform vec2 scan_dir = vec2(1.0, 0.0);
uniform float half_extent = 0.15;
uniform float row_count = 64.0;
uniform float step_seed = 0.0;
uniform float frame_aspect = 1.7777778;

uniform float density = 1.0;
uniform float stretch = 0.0;
uniform float stagger = 0.0;
uniform float line_width = 1.0;
uniform float concentration = 0.0;
uniform float anchor = 0.0;
uniform float alpha_gain = 1.0;

float row_random(float row, float salt) {
	return fract(sin(row * 78.233 + step_seed * 12.9898 + salt * 39.425) * 43758.5453123);
}

void fragment() {
	vec2 aspect = vec2(frame_aspect, 1.0);
	vec2 perp = vec2(-scan_dir.y, scan_dir.x);
	vec2 q = (UV - centroid) * aspect;
	float s = dot(q, scan_dir);
	float t = dot(q, perp);

	float rows = max(row_count / max(half_extent * 2.0, 1e-4), 4.0);
	float row = floor(t * rows);

	float t_norm = clamp(abs(t) / max(half_extent, 1e-4), 0.0, 1.0);
	float keep_prob = density * mix(1.0, 1.0 - t_norm, concentration);
	if (row_random(row, 0.0) > keep_prob) {
		discard;
	}

	if (fract(t * rows) > line_width) {
		discard;
	}

	float k = 1.0 + stretch * (0.5 + row_random(row, 1.0));
	float s2 = (s - anchor) / k + anchor + (row_random(row, 2.0) - 0.5) * stagger;

	vec2 uv2 = src_centroid + (s2 * scan_dir + t * perp) / aspect;
	if (uv2.x < 0.0 || uv2.x > 1.0 || uv2.y < 0.0 || uv2.y > 1.0) {
		discard;
	}

	vec4 src = texture(src_tex, uv2);
	if (src.a <= 0.001) {
		discard;
	}
	ALBEDO = src.rgb;
	ALPHA = src.a * alpha_gain / k;
}
