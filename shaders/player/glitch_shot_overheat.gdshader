shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// The shotgun while the glitch shot is armed (scripts/weapons/shotgun.gd): the gun is being shot to pieces and is
// overheating. Drawn as an overlay on the gun. The barrel is the hottest, white-hot, and the heat falls away to dull
// red towards the butt. A heat wave rolls from the barrel back to the butt: the gun's own image ripples and shimmers
// as the wave passes, slow bands of heat roll with it, and a heartbeat pulse follows every second or so. Now and then a
// thin slice of the gun glitches. Everything is slow and smooth on purpose.
//
// The model is long along its Z axis: the barrel end is at z = barrel_z and the butt at z = butt_z (model space, before
// the weapon node scales it). The pump is a separate mesh offset from the body, so it gets `local_offset` to put it
// back into body space.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform vec3 local_offset = vec3(0.0);
uniform float barrel_z = -0.85;
uniform float butt_z = 0.54;
uniform float intensity : hint_range(0.0, 1.5) = 1.0;     // ramps up when the glitch shot arms
uniform float pulse_rate = 0.7;                            // heartbeats a second
uniform float wave_speed = 2.2;                            // how fast the heat wave rolls towards the butt
uniform float shimmer = 0.006;                             // how far the wave ripples the gun's image, in screen widths
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

float along(vec3 p) {
	return clamp((p.z - barrel_z) / (butt_z - barrel_z), 0.0, 1.0);   // 0 at the barrel, 1 at the butt
}

void vertex() {
	body_pos = VERTEX + local_offset;
	float t = along(body_pos);
	// The heat wave swells the gun outward as it passes
	float wave = sin(t * 20.0 - TIME * wave_speed * 2.0);
	VERTEX += NORMAL * wave * 0.012 * (1.0 - t);
	// Glitch slices: a thin cross-section of the gun slips sideways, now and then
	float slice = floor(body_pos.z * 22.0);
	float tick = floor(TIME * 3.0);
	float jump = step(0.965, hash(slice * 1.37 + tick * 7.1)) * glitch_amount;
	VERTEX.x += (hash(slice + tick) - 0.5) * 0.025 * jump;
}

void fragment() {
	float t = along(body_pos);
	float base = pow(1.0 - t, 1.4);

	// The heat wave: soft broad bands of heat rolling from the barrel to the butt, strongest near the barrel
	float roll = 0.5 + 0.5 * sin(t * 12.0 - TIME * wave_speed);
	roll = smoothstep(0.1, 0.95, roll);

	// The heartbeat: a bright front that leaves the barrel and runs back to the butt, fading as it goes
	float beat = fract(TIME * pulse_rate);
	float front = beat * 1.2;
	float ring = 1.0 - smoothstep(0.0, 0.22, abs(t - front));
	ring *= (1.0 - beat) * (1.0 - beat);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);

	// Rare glitch slices flash white, with faint scanlines through everything
	float slice = floor(body_pos.z * 22.0);
	float tick = floor(TIME * 3.0);
	float flash = step(0.965, hash(slice * 1.37 + tick * 7.1)) * glitch_amount;
	float scan = 0.94 + 0.06 * sin(body_pos.y * 160.0 - TIME * 6.0);

	float heat = clamp(base * (0.5 + 0.5 * roll) + ring * 0.7 + rim * 0.25 * (0.3 + base), 0.0, 1.0);
	vec3 glow = heat_ramp(heat) * (0.25 + heat * 1.1);
	glow = mix(glow, vec3(1.0, 0.9, 0.8), flash * 0.5);

	// The gun's own image, rippled by the passing wave: strongest near the barrel
	float ripple = sin(t * 26.0 - TIME * wave_speed * 2.4 + body_pos.y * 8.0);
	vec2 offset = vec2(ripple * 0.35, ripple) * shimmer * (1.0 - t) * intensity;
	vec3 gun = texture(screen_texture, SCREEN_UV + offset).rgb;

	ALBEDO = (gun + glow * scan * intensity * (0.9 + 0.1 * ripple)) ;
	ALPHA = 1.0;
}
