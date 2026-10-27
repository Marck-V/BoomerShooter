shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The faint column of light rising out of a launchpad portal: streaks that drift upward and fade with height.
// Put on an open-ended cylinder whose bottom is at the portal; `height` must match the mesh height.

uniform vec3 beam_color : source_color = vec3(0.6, 0.2, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 0.6;
uniform float height = 2.4;
uniform float streaks = 14.0;
uniform float rise_speed = 0.7;

varying float h;

void vertex() {
	// The cylinder is centred on its node, so lift the local y into 0 (bottom) .. 1 (top)
	h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	float angle = UV.x * streaks;
	float streak = 0.5 + 0.5 * sin(angle * 6.2831853 + h * 4.0);
	streak = smoothstep(0.55, 1.0, streak);
	float scroll = fract(h * 2.5 - TIME * rise_speed + UV.x * 3.0);
	float band = smoothstep(0.0, 0.2, scroll) * (1.0 - smoothstep(0.35, 0.7, scroll));
	float fade = pow(1.0 - h, 1.6) * smoothstep(0.0, 0.06, h);
	// Brighter where the surface turns away from the camera, so the column reads as a soft glowing shell
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.5);
	float amount = fade * (0.15 + 0.55 * streak * band + 0.5 * rim);
	ALBEDO = beam_color * 2.0;
	ALPHA = clamp(amount * intensity, 0.0, 1.0);
}
