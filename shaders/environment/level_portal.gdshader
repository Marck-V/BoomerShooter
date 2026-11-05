shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// The doorway of the level exit: streaks of coloured light racing diagonally across a dark void, like a
// long-exposure of light trails: hot orange and yellow on one side, blue, magenta and cyan across the rest, with
// soft blurred smears behind the sharp streaks. Drawn on a quad that fills the door frame (UV 0..1).

uniform float open : hint_range(0.0, 1.0) = 1.0;            // the doorway reveals from its middle outwards
uniform float speed = 0.5;
uniform float angle = 0.62;                                   // radians: how far the streaks tilt from vertical
uniform float aspect = 0.66;                                  // width / height of the doorway
uniform float brightness : hint_range(0.0, 4.0) = 1.6;        // over 1.0 so the glow effect picks the bright parts up
uniform float flash : hint_range(0.0, 4.0) = 0.0;             // a quick white-hot surge when something walks in
uniform vec3 hot_color : source_color = vec3(1.0, 0.5, 0.06);
uniform float posterize_steps = 0.0;                          // >0 for chunky colour bands to match the PSX look

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// Orange, yellow, magenta, blue, cyan and back: the colours of the light trails
vec3 palette(float t) {
	vec3 c0 = vec3(1.0, 0.42, 0.04);
	vec3 c1 = vec3(1.0, 0.85, 0.18);
	vec3 c2 = vec3(1.0, 0.12, 0.55);
	vec3 c3 = vec3(0.12, 0.32, 1.0);
	vec3 c4 = vec3(0.08, 0.88, 1.0);
	t = fract(t) * 5.0;
	float f = fract(t);
	f = f * f * (3.0 - 2.0 * f);
	if (t < 1.0) return mix(c0, c1, f);
	if (t < 2.0) return mix(c1, c2, f);
	if (t < 3.0) return mix(c2, c3, f);
	if (t < 4.0) return mix(c3, c4, f);
	return mix(c4, c0, f);
}

// One family of streaks: lanes across the door, each with its own speed, colour and gaps along its length
vec3 streaks(vec2 p, float lanes, float width, float stretch, float lane_speed, float seed, float presence) {
	float across = p.x * lanes;
	float id = floor(across);
	float f = fract(across) - 0.5;
	float r = hash11(id * 7.13 + seed);
	float r2 = hash11(id * 3.77 + seed * 1.7);
	float along = p.y * stretch + TIME * speed * lane_speed * (0.4 + r) + r2 * 40.0;
	float seg = floor(along);
	float t = fract(along);
	// Each streak fades in softly along its length and ends in a tail; some segments are simply dark
	float present = step(presence, hash11(id * 1.31 + seg * 5.7 + seed));
	float body = smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.3, t);
	float w = width * (0.35 + r);
	float line = smoothstep(w, 0.0, abs(f));
	float core = smoothstep(w * 0.3, 0.0, abs(f));
	vec3 col = palette(0.07 * floor(across / 3.0) + p.x * 0.22 + r2 * 0.18 + TIME * 0.02);
	return (col * line + vec3(1.0, 0.95, 0.85) * core * 0.22) * body * present;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	vec2 q = vec2(uv.x * aspect, uv.y);
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 p = vec2(ca * q.x - sa * q.y, sa * q.x + ca * q.y);

	vec3 col = vec3(0.0);
	// Sharp trails, fine and fast to broad and slow, plus wide soft smears that give it its motion blur
	col += streaks(p, 16.0, 0.06, 2.4, 1.7, 1.0, 0.7) * 1.0;
	col += streaks(p, 8.0, 0.1, 1.4, 1.2, 5.0, 0.6) * 1.0;
	col += streaks(p, 4.0, 0.3, 0.8, 0.8, 9.0, 0.55) * 0.9;
	col += streaks(p, 2.2, 0.5, 0.5, 0.5, 13.0, 0.6) * 0.9;

	// A hot glow pooling in one corner, and colour drifting slowly through the rest
	float corner = exp(-length(uv - vec2(-0.75, -0.55)) * 1.8);
	col += hot_color * corner * corner * 0.9;
	float drift = 0.5 + 0.5 * sin(p.x * 3.0 + p.y * 1.5 - TIME * 0.4);
	col += palette(p.x * 0.3 - TIME * 0.03 + 0.4) * drift * 0.03;

	// The doorway is a little darker at its edges, so the light seems to come out of the depth of it
	float edge = max(abs(uv.x), abs(uv.y));
	col *= mix(0.3, 1.0, smoothstep(1.0, 0.5, edge));
	col += vec3(1.0, 0.9, 0.7) * flash * (0.3 + 0.7 * smoothstep(1.0, 0.0, edge));

	// Contrast: deep black between the trails, saturated colour in them
	col = pow(col, vec3(1.45));
	col *= brightness;
	if (posterize_steps > 0.0) {
		col = floor(col * posterize_steps + 0.5) / posterize_steps;
	}
	ALBEDO = col;
	// Opens from the middle of the door outwards
	ALPHA = smoothstep(open * 1.1, open * 1.1 - 0.1, abs(uv.y)) * step(0.001, open);
}
