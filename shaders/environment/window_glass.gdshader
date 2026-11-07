shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Window glass: nearly clear, with a cool tint, a bright rim at glancing angles, two soft diagonal glints that
// slide across as you move, and faint grime. Once the pane is hit, a spider-web of cracks spreads from the impact
// point (`damage` is 0 for an intact pane and 1 just before it shatters). Works on any flat pane in any orientation.

uniform vec4 tint : source_color = vec4(0.12, 0.28, 0.36, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.1;      // how much of the glass shows face-on
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;    // higher keeps the rim thinner
uniform float fresnel_alpha : hint_range(0.0, 1.0) = 0.55;   // extra opacity at the rim
uniform float glint_strength : hint_range(0.0, 2.0) = 0.35;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.25;
uniform float emission_boost : hint_range(0.0, 4.0) = 0.5;   // over 1 so the glow picks up the glints

uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec3 impact_point = vec3(0.0);                       // world space
uniform vec3 pane_right = vec3(1.0, 0.0, 0.0);               // world directions along the pane's width and height
uniform vec3 pane_up = vec3(0.0, 1.0, 0.0);
uniform float shatter_flash : hint_range(0.0, 1.0) = 0.0;    // brief white-out when hit

uniform float inset = 0.0;                                   // pulls every face in along its normal, so a pane fitted flush into a frame doesn't share surfaces with it

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

// Spider-web cracks around the impact point: lines running outwards plus rings joining them
float cracks(vec3 pos) {
	vec3 d = pos - impact_point;
	vec3 right = normalize(pane_right);
	vec2 q = vec2(dot(d, right), dot(d, normalize(pane_up)));
	float r = length(q);
	float a = atan(q.y, q.x);

	// Radial cracks: a few dozen, each wobbling a little as it goes out
	float wobble = (noise21(vec2(a * 6.0, r * 5.0)) - 0.5) * 0.35;
	float rays = 22.0;
	float ray_pos = (a + wobble) / 6.28318 * rays;
	float ray_id = floor(ray_pos);
	float ray_len = 0.25 + 1.4 * hash21(vec2(ray_id, 3.0));              // each one only reaches so far
	float ray = smoothstep(0.06, 0.0, abs(fract(ray_pos) - 0.5) * (0.6 + r * 0.9)) * step(r, ray_len);

	// Rings: uneven polygons around the impact, only where a ray is nearby
	float ring_r = r * 7.0 + (noise21(vec2(a * 3.0, 1.0)) - 0.5) * 0.9;
	float ring = smoothstep(0.08, 0.0, abs(fract(ring_r) - 0.5)) * step(r, 0.2 + damage * 1.3);

	float crushed = smoothstep(0.16, 0.0, r);                            // the impact itself is a crushed white patch
	return clamp(ray + ring * 0.7 + crushed, 0.0, 1.0);
}

void vertex() {
	VERTEX -= NORMAL * inset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float facing = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);

	// Diagonal glints: bands across the pane that slide with the viewing angle, as light does on real glass
	float across = world_pos.x + world_pos.z;
	float diag = world_pos.y * 0.9 + across * 0.55 + dot(VIEW, vec3(0.7, 0.0, 0.7)) * 0.6;
	float band1 = smoothstep(0.07, 0.0, abs(fract(diag * 0.35 + 0.1) - 0.5));
	float band2 = smoothstep(0.02, 0.0, abs(fract(diag * 0.35 - 0.04) - 0.5));
	float glint = (band1 * 0.55 + band2) * glint_strength;

	float grime = (noise21(world_pos.xy * 3.1 + world_pos.zz * 3.1) * 0.6 + noise21(world_pos.xy * 11.0 + world_pos.zz * 11.0) * 0.4);
	grime = smoothstep(0.55, 0.9, grime) * grime_strength;

	float crack = cracks(world_pos) * damage;

	vec3 col = tint.rgb;
	col += vec3(0.8, 0.95, 1.0) * (fresnel * 0.6 + glint);
	col = mix(col, vec3(0.5, 0.55, 0.55), grime);
	col = mix(col, vec3(0.95, 0.98, 1.0), crack);
	col = mix(col, vec3(1.0), shatter_flash);

	float alpha = base_alpha + fresnel * fresnel_alpha + glint * 0.35 + grime * 0.4 + crack * 0.75 + shatter_flash * 0.6;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.92);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	EMISSION = (vec3(0.7, 0.9, 1.0) * (glint * 0.5 + fresnel * 0.25) + vec3(1.0) * crack * 0.25) * emission_boost;
}
