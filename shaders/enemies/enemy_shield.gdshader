// The enemy shield's crystal cage (models/enemy_shield/enemy_shield.glb, built by tools/assetgen/enemy_shield.py).
// The cage is 80 loose tiles, a translucent pane in a glowing rim. Every vertex carries its tile's data:
//     UV  = tile centre x, y        UV2 = tile centre z, seed (0-1 on a pane, 2-3 on a rim)
// so a hit lights whole panes around the hit point, and on break every tile flies off from the centre on its own.
// Additive and unshaded, so the tiles never need sorting.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(0.05, 0.85, 1.0, 1.0);
uniform vec4 pane_color : source_color = vec4(0.05, 0.6, 1.0, 1.0);
uniform float rim_energy = 2.5;
uniform float pane_energy = 0.18;
uniform float edge_boost = 0.5;         // panes facing sideways to the camera are brighter

group_uniforms hit_flash;
uniform vec4 flash_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform vec3 hit_points[8];             // in the cage's own space
uniform float hit_strengths[8];         // 1 when hit, fading to 0; shield.gd runs these
uniform float hit_radius = 0.45;        // panes whose centre is this close to a hit light up
uniform float flash_energy = 2.2;

group_uniforms shatter;
uniform float shatter_time = -1.0;      // seconds since the shield broke, below 0 while it's whole
uniform float shatter_length = 0.9;
uniform vec3 shatter_centre = vec3(0.0, 1.0, 0.0);
uniform vec3 shatter_hit = vec3(0.0, 1.0, -1.0);  // where the last hit landed: tiles there fly hardest
uniform float shatter_speed = 2.4;
uniform float shatter_gravity = 9.0;
uniform float shatter_spin = 9.0;

varying float v_flash;
varying float v_rim;
varying float v_fade;
varying float v_pop;

vec3 rotate(vec3 p, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

void vertex() {
	vec3 centre = vec3(UV.x, UV.y, UV2.x);
	float seed = fract(UV2.y);
	v_rim = step(1.5, UV2.y);

	v_flash = 0.0;
	for (int i = 0; i < 8; i++) {
		v_flash = max(v_flash, smoothstep(hit_radius, 0.0, distance(centre, hit_points[i])) * hit_strengths[i]);
	}

	v_fade = 1.0;
	v_pop = 0.0;
	if (shatter_time >= 0.0) {
		float t = shatter_time;
		float progress = clamp(t / shatter_length, 0.0, 1.0);
		vec3 out_dir = normalize(centre - shatter_centre + vec3(0.0, 0.001, 0.0));
		vec3 from_hit = centre - shatter_hit;
		float near_hit = smoothstep(1.6, 0.0, length(from_hit));
		vec3 dir = normalize(out_dir + normalize(from_hit + vec3(0.0, 0.001, 0.0)) * near_hit * 0.8);
		float speed = shatter_speed * (0.6 + seed * 0.8) * (1.0 + near_hit);
		vec3 moved = centre + dir * speed * t + vec3(0.0, 1.2, 0.0) * t - vec3(0.0, 0.5 * shatter_gravity * t * t, 0.0);
		vec3 axis = normalize(vec3(seed - 0.5, fract(seed * 7.13) - 0.5, fract(seed * 3.71) - 0.5) + vec3(0.001));
		float shrink = 1.0 - smoothstep(0.45, 1.0, progress);
		VERTEX = moved + rotate(VERTEX - centre, axis, shatter_spin * (0.5 + seed) * t) * shrink;
		v_fade = 1.0 - progress;
		v_pop = 1.0 - smoothstep(0.0, 0.2, t);  // white-hot for a moment as it breaks
	}
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), VIEW));
	vec3 base = v_rim > 0.5 ? rim_color.rgb * rim_energy : pane_color.rgb * pane_energy * (1.0 + edge_boost * (1.0 - facing));
	vec3 flash = flash_color.rgb * flash_energy * v_flash * (v_rim > 0.5 ? 1.0 : 0.35);
	vec3 pop = vec3(1.0) * 3.0 * v_pop;
	ALBEDO = (base + flash + pop) * v_fade;
}
