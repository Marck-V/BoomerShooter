shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The glowing ring of the boss's shockwave on the floor, drawn on a flat plane as big as the wave's full reach.
// `ring_radius` is the wave's current radius as a fraction of that reach (0..1).

uniform vec3 color : source_color = vec3(1.0, 0.4, 0.1);
uniform float ring_radius : hint_range(0.0, 1.0) = 0.0;
uniform float ring_width : hint_range(0.001, 0.3) = 0.035;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float d = r - ring_radius;
	float band = 1.0 - smoothstep(0.0, ring_width, abs(d));
	// A fading trail of heat behind the front
	float trail = smoothstep(-0.22, 0.0, d) * (1.0 - smoothstep(0.0, 0.01, d)) * 0.35;
	float amount = clamp(band + trail, 0.0, 1.0) * fade;
	ALBEDO = color * 2.4;   // over 1.0 so the glow effect picks it up
	ALPHA = amount;
}
