shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The vortex disc of a launchpad: swirling purple energy that spirals into a bright core, with a glowing
// rim. Drawn additively on a flat plane lying on the ground (UV 0..1 across the plane).

uniform vec3 deep_color : source_color = vec3(0.14, 0.0, 0.34);
uniform vec3 energy_color : source_color = vec3(0.62, 0.15, 1.0);
uniform vec3 hot_color : source_color = vec3(0.95, 0.6, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float flash : hint_range(0.0, 4.0) = 0.0;          // pulses up when something is launched
uniform float spin_speed = 0.9;
uniform float arms = 5.0;
uniform float posterize_steps = 6.0;                         // chunky colour bands to match the PSX look; 0 = smooth

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);

	// Spiral arms, wound tighter towards the centre and turning with time
	float swirl = a * arms + (1.0 - r) * 7.0 - TIME * spin_speed * arms;
	float arm = smoothstep(0.25, 1.0, 0.5 + 0.5 * sin(swirl));
	// A slower counter-rotating layer for depth
	float arm2 = smoothstep(0.4, 1.0, 0.5 + 0.5 * sin(a * 3.0 - (1.0 - r) * 4.0 + TIME * spin_speed * 1.6));
	// Rings pulsing inwards, like the portal is drawing in
	float rings = 0.5 + 0.5 * sin(r * 22.0 + TIME * 3.0);

	float body = smoothstep(0.0, 0.85, r);
	float core = pow(1.0 - r, 3.0);
	float rim = smoothstep(0.72, 0.9, r) * (1.0 - smoothstep(0.93, 1.0, r));

	float energy = clamp(arm * 0.9 + arm2 * 0.45 + rings * 0.12, 0.0, 1.0);
	vec3 col = deep_color * (0.3 + 0.5 * body);
	col = mix(col, energy_color, energy * body);
	col += hot_color * core * 0.8;
	col += mix(energy_color, hot_color, 0.45) * rim * 1.1;

	if (posterize_steps > 0.5) {
		col = floor(col * posterize_steps + 0.5) / posterize_steps;
	}

	float edge = 1.0 - smoothstep(0.9, 1.0, r);
	float alpha = clamp((0.35 + 0.65 * energy + core + rim) * edge, 0.0, 1.0);
	ALBEDO = col * (1.0 + flash) * intensity * 1.6;   // over 1.0 so the glow effect picks it up
	ALPHA = alpha;
}
