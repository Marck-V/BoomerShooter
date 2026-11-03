shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A glowing disc on the floor (see BeaconPad): a solid outer ring, a ring of ticks turning slowly inside it, and
// pulses spreading out from the centre. Drawn on a flat plane lying on the ground (UV 0..1).

uniform vec3 idle_color : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 active_color : source_color = vec3(0.3, 1.0, 0.4);
uniform float active : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 4.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float ticks = 16.0;
uniform float spin_speed = 0.12;   // turns per second

float band(float r, float at, float half_width) {
	return 1.0 - smoothstep(0.0, half_width, abs(r - at));
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	if (r > 1.0) {
		discard;
	}
	float turn = atan(q.y, q.x) / 6.2831853;

	float outer = band(r, 0.92, 0.05);
	float tick = step(0.55, fract(turn * ticks + TIME * spin_speed * ticks)) * band(r, 0.76, 0.06);
	float inner = band(r, 0.52, 0.025);
	float pulse = band(r, fract(TIME * 0.45), 0.06) * (1.0 - r);
	float fill = (1.0 - r) * 0.12;

	float amount = outer + tick * 0.8 + inner * 0.6 + pulse * 0.7 + fill + flash * (1.0 - r) * 0.8;
	vec3 col = mix(idle_color, active_color, active);
	col = mix(col, vec3(1.0), clamp(flash * 0.4, 0.0, 0.7));
	ALBEDO = col * 1.8;   // over 1.0 so the glow effect picks it up
	ALPHA = clamp(amount * intensity * (1.0 - smoothstep(0.96, 1.0, r)), 0.0, 1.0);
}
