shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// Curtain of light high in the sky: vertical streaks that ripple in stepped time.
// UV.x runs along the arc, UV.y from the bottom edge (0) to the top (1).

uniform vec3 color_low : source_color = vec3(0.1, 1.0, 0.7);
uniform vec3 color_high : source_color = vec3(1.0, 0.2, 0.9);
uniform float streaks = 70.0;

void fragment() {
	float t = floor(TIME * 8.0) / 8.0;
	float curtain = 0.5 + 0.5 * sin(UV.x * streaks + t * 1.5 + sin(UV.x * 13.0 + t) * 2.0);
	curtain = floor(curtain * 4.0) / 4.0;
	float fade = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.45, 1.0, UV.y));
	ALBEDO = mix(color_low, color_high, UV.y) * 1.3;
	ALPHA = curtain * fade;
}
