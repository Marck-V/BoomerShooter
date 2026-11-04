shader_type spatial;
render_mode specular_schlick_ggx;

// The hand boss arena's floor: glossy water that mirrors the sky, with cyan streaks drifting across it and
// slow magenta glints. Patterns come from world position, so it lines up across brushes whatever their UVs.

uniform vec3 deep_color : source_color = vec3(0.01, 0.10, 0.16);
uniform vec3 streak_color : source_color = vec3(0.25, 0.95, 1.0);
uniform vec3 glint_color : source_color = vec3(1.0, 0.35, 0.65);
uniform float pattern_scale = 0.06;   // patterns per meter
uniform float streak_stretch = 5.0;   // streaks are this much longer than they are wide
uniform float flow_speed = 0.04;
uniform float ripple_strength = 0.35;
uniform float glow = 0.35;            // how much the streaks light themselves

// Rings spreading out from where something touched the water. Set from code by WaterRipple
// (scripts/environment/water_ripple.gd): each is (world x, world z, age in seconds, strength). The script fades
// the strength out over the ripple's life; zero strength is an empty slot.
const int MAX_RIPPLES = 4;
uniform vec4 touch_ripples[MAX_RIPPLES];
uniform float ripple_speed = 9.0;          // meters per second
uniform float ripple_wavelength = 2.4;     // meters between rings
uniform float ripple_train = 9.0;          // how far behind the front rings still show, meters
uniform vec3 ripple_color : source_color = vec3(0.55, 1.0, 1.0);

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
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

float ripples(vec2 p, float t) {
	return fbm(p * 6.0 + vec2(t * 3.0, -t * 2.0));
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz * pattern_scale;
	float t = TIME * flow_speed;

	float streaks = fbm(p * vec2(1.0, streak_stretch) + vec2(t, 0.0));
	float glints = fbm(p * 2.5 - vec2(0.0, t * 1.5));
	float streak_mask = smoothstep(0.45, 0.75, streaks);
	float glint_mask = smoothstep(0.68, 0.85, glints);

	vec3 color = mix(deep_color, streak_color, streak_mask);
	color = mix(color, glint_color, glint_mask * 0.5);
	ALBEDO = color;
	EMISSION = color * glow * (0.4 + streak_mask);
	METALLIC = 0.55;
	ROUGHNESS = mix(0.04, 0.22, streak_mask);

	// Bumps from the ripple pattern's slope
	float e = 0.02;
	float h = ripples(p, t);
	float hx = ripples(p + vec2(e, 0.0), t);
	float hz = ripples(p + vec2(0.0, e), t);
	vec2 slope = vec2(hx - h, hz - h) / e * ripple_strength * 0.05;

	// Rings from touches: a train of waves behind each expanding front, fading with age and distance
	float crest_glow = 0.0;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 ripple = touch_ripples[i];
		if (ripple.z < 0.0 || ripple.w <= 0.0) {
			continue;
		}
		vec2 offset = world.xz - ripple.xy;
		float dist = length(offset);
		float behind = ripple.z * ripple_speed - dist;   // how far inside the front this point is
		if (behind <= 0.0 || behind > ripple_train) {
			continue;
		}
		float fade = 1.0 - behind / ripple_train;
		fade *= ripple.w / (1.0 + dist * 0.04) * smoothstep(0.0, ripple_wavelength * 0.5, behind);
		float wave_phase = behind / ripple_wavelength * 6.2832;
		vec2 outward = dist > 0.001 ? offset / dist : vec2(0.0);
		slope += outward * cos(wave_phase) * fade * 0.9;
		crest_glow += pow(max(sin(wave_phase), 0.0), 3.0) * fade;
	}
	EMISSION += ripple_color * crest_glow * 0.9;
	ROUGHNESS = mix(ROUGHNESS, 0.02, clamp(crest_glow, 0.0, 1.0));

	NORMAL_MAP = normalize(vec3(-slope.x, -slope.y, 1.0)) * 0.5 + 0.5;
}
