shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The tear in the sky the hand boss reaches through: a ragged hole onto a dark dimension. Inside, near-black
// void with a faint nebula swirling down into it and a few distant stars; around it, a crackling violet edge and
// a soft dark halo, as if the darkness is bleeding out. Drawn on a flat plane (UV 0..1 across it).
// open_amount runs 0 (shut) to 1 (fully open), for opening and closing it.

uniform vec3 void_color : source_color = vec3(0.005, 0.0, 0.015);
uniform vec3 nebula_color : source_color = vec3(0.22, 0.02, 0.36);
uniform vec3 rim_color : source_color = vec3(0.6, 0.12, 1.0);
uniform vec3 rim_hot_color : source_color = vec3(1.0, 0.65, 1.0);
uniform vec3 halo_color : source_color = vec3(0.02, 0.0, 0.05);
uniform float open_amount : hint_range(0.0, 1.0) = 1.0;
uniform float edge_radius = 0.8;        // of the plane's half-size, when fully open
uniform float raggedness = 0.16;
uniform float rim_width = 0.035;
uniform float rim_brightness = 2.2;
uniform float halo_width = 0.2;
uniform float halo_opacity = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * noise(p);
		p = p * 2.07 + vec2(3.1, 7.7);
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	vec2 around = vec2(cos(angle), sin(angle));   // seamless all the way round
	float t = TIME;

	// The tear's edge wanders, and keeps shifting
	float wobble = fbm(around * 2.2 + vec2(t * 0.25, -t * 0.18)) - 0.5;
	float edge = (edge_radius + wobble * raggedness) * open_amount;
	float inside = 1.0 - smoothstep(edge - 0.015, edge + 0.015, r);

	// The void: a nebula swirling inwards, darkest in the middle, with distant stars
	float swirl = angle + t * 0.12 + 1.8 / (r + 0.3);
	vec2 q = vec2(cos(swirl), sin(swirl)) * r * 2.6;
	float nebula = fbm(q + vec2(t * 0.05, 0.0));
	float depth = smoothstep(0.0, max(edge, 0.001), r);
	vec3 color = mix(void_color, nebula_color, nebula * nebula * (0.25 + 0.75 * depth));
	vec2 star_cell = floor(q * 9.0);
	float star = step(0.992, hash(star_cell)) * (0.5 + 0.5 * sin(t * 3.0 + hash(star_cell + 1.0) * 6.28));
	color += vec3(0.75, 0.55, 1.0) * star * (1.0 - depth * 0.6);

	// The crackling edge
	float crackle = fbm(around * 7.0 + vec2(t * 1.6, t * 0.4));
	float rim = exp(-abs(r - edge) / rim_width) * step(0.001, open_amount);
	vec3 rim_glow = mix(rim_color, rim_hot_color, smoothstep(0.55, 0.85, crackle)) * rim_brightness * (0.6 + crackle);

	// Darkness bleeding out round it
	float halo = (1.0 - smoothstep(edge, edge + halo_width, r)) * (1.0 - inside) * open_amount;

	vec3 final_color = mix(halo_color, color, inside);
	final_color += rim_glow * rim;
	ALBEDO = final_color;
	ALPHA = clamp(max(inside, max(rim, halo * halo_opacity)), 0.0, 1.0) * step(r, 1.0);
}
