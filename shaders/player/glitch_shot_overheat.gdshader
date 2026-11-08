shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// The shotgun while the glitch shot is armed (scripts/weapons/shotgun.gd): the gun is overheating. Drawn as a purely
// additive glow laid on top of the gun's own textures; it never moves, distorts or resamples them. The barrel is the
// hottest, white-hot, and the heat falls away to dull red towards the butt. Evenly spaced, identical pulses of heat run
// from the barrel to the butt. Now and then a thin slice of the gun flashes.
//
// The model is long along its Z axis: the barrel end is at z = barrel_z and the butt at z = butt_z (model space, before
// the weapon node scales it). The pump is a separate mesh offset from the body, so it gets `local_offset` to put it
// back into body space.

uniform vec3 local_offset = vec3(0.0);
uniform float barrel_z = -0.85;
uniform float butt_z = 0.54;
uniform float intensity : hint_range(0.0, 1.5) = 1.0;     // ramps up when the glitch shot arms
uniform float pulse_rate = 0.8;                            // how many pulses pass any point on the gun each second
uniform float pulse_count = 3.0;                           // how many pulses fit along the gun at once
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.35;

varying vec3 body_pos;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

vec3 heat_ramp(float h) {
	// dull blood red at the butt, through red and orange, to white-hot at the barrel
	vec3 c = mix(vec3(0.35, 0.0, 0.02), vec3(1.0, 0.08, 0.03), smoothstep(0.0, 0.4, h));
	c = mix(c, vec3(1.0, 0.45, 0.08), smoothstep(0.4, 0.75, h));
	return mix(c, vec3(1.0, 0.95, 0.8), smoothstep(0.78, 1.0, h));
}

// Evenly spaced, identical pulses that all travel from the barrel (t = 0) to the butt (t = 1) in one direction.
float pulse(float t) {
	float q = fract(TIME * pulse_rate - t * pulse_count);   // 0 at the front, grows behind it
	float rise = smoothstep(0.0, 0.3, q);
	float tail = 1.0 - smoothstep(0.0, 1.0, q);
	return rise * tail * tail * 1.6;
}

float along(vec3 p) {
	return clamp((p.z - barrel_z) / (butt_z - barrel_z), 0.0, 1.0);   // 0 at the barrel, 1 at the butt
}

void vertex() {
	body_pos = VERTEX + local_offset;
	// Nudge the overlay a hair along the normal so it doesn't z-fight with the gun; the geometry is not otherwise moved.
	VERTEX += NORMAL * 0.002;
}

void fragment() {
	float t = along(body_pos);
	float base = pow(1.0 - t, 1.4);
	float ring = pulse(t);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);

	// Faint scanlines through everything (the hard-edged glitch slice flashes were removed: they cut visible bands)
	float scan = 0.94 + 0.06 * sin(body_pos.y * 160.0 - TIME * 6.0);

	float heat = clamp(base * 0.6 + ring * 0.4 + rim * 0.25 * (0.3 + base), 0.0, 1.0);
	vec3 glow = heat_ramp(heat) * (0.25 + heat * 1.1);

	// Tint, not add: the heat colour is mixed over the gun so every part (barrel, receiver, stock) lands on the same
	// colour whatever its own texture brightness, while the texture still shows through underneath.
	ALBEDO = glow * scan;
	ALPHA = clamp(0.6 * intensity, 0.0, 1.0);
}
