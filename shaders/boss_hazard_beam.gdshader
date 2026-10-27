shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The column of fire that shoots up out of a burning floor tile. Put on an open-ended cylinder whose middle is
// at half of `height`: a hot core that fades with height, energy streaks racing upwards, and a flash at the
// moment it ignites. `fade` takes the whole thing out at the end.

uniform vec3 beam_color : source_color = vec3(1.0, 0.25, 0.08);
uniform vec3 core_color : source_color = vec3(1.0, 0.85, 0.5);
uniform float height = 12.0;
uniform float intensity : hint_range(0.0, 4.0) = 0.55;
uniform float radius = 1.6;                                 // of the cylinder, so the beam can fade out around the camera
uniform float flash : hint_range(0.0, 4.0) = 0.0;           // a brief extra glow as it ignites
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float streaks = 9.0;
uniform float rise_speed = 2.4;

varying float h;

void vertex() {
	h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	float angle = UV.x * streaks;
	float streak = smoothstep(0.45, 1.0, 0.5 + 0.5 * sin(angle * 6.2831853 + h * 3.0));
	float scroll = fract(h * 3.0 - TIME * rise_speed + UV.x * 2.0);
	float band = smoothstep(0.0, 0.25, scroll) * (1.0 - smoothstep(0.3, 0.8, scroll));
	float base_fade = pow(1.0 - h, 1.3) * smoothstep(0.0, 0.03, h);
	// Brighter towards the edges of the cylinder as seen from the side gives a soft glowing shell
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.2);
	float hot = pow(1.0 - h, 4.0);                              // white-hot near the floor
	float amount = base_fade * (0.35 + 0.5 * streak * band + 0.55 * rim) * (1.0 + flash);
	vec3 col = mix(beam_color, core_color, hot * 0.5);
	// Seen from inside (or right next to it) the beam fades away, so standing in a burning tile does not blind you
	vec2 to_camera = (CAMERA_POSITION_WORLD - NODE_POSITION_WORLD).xz;
	float clearance = smoothstep(radius * 0.7, radius * 1.8, length(to_camera));
	ALBEDO = col * 1.8;
	ALPHA = clamp(amount * intensity * fade * mix(0.05, 1.0, clearance), 0.0, 1.0);
}
