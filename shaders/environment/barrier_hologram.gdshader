shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A red holographic energy wall (the combat barriers). A faint grid with brighter lines, scan bands that drift up it,
// a glow on its edges and where it is thin to the eye, and a flicker. `reveal` runs 0 to 1: the wall is drawn up from
// the floor, with a hot line at the leading edge, and drawn away the same way when it drops.

uniform vec4 color : source_color = vec4(1.0, 0.06, 0.04, 1.0);
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float y_bottom = 0.0;
uniform float y_top = 4.0;
uniform float intensity = 1.6;
uniform float grid_size = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float height = clamp((world_pos.y - y_bottom) / max(y_top - y_bottom, 0.001), 0.0, 1.0);
	if (height > reveal) {
		discard;
	}
	// Along the wall: the wall runs along x or z, so their sum measures the distance along it either way
	float along = world_pos.x + world_pos.z;
	vec2 cell = vec2(along, world_pos.y) / grid_size;
	vec2 edge = abs(fract(cell) - 0.5);
	float lines = smoothstep(0.44, 0.5, max(edge.x, edge.y));
	float scan = 0.5 + 0.5 * sin(world_pos.y * 26.0 - TIME * 5.0);
	float drift = smoothstep(0.85, 1.0, fract(height * 1.5 - TIME * 0.35)) * 0.6;
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float flicker = 0.9 + 0.1 * sin(TIME * 37.0 + along * 2.0) * sin(TIME * 6.3);
	float leading = (reveal < 0.999) ? smoothstep(reveal - 0.06, reveal, height) * 1.5 : 0.0;
	float rims = smoothstep(0.93, 1.0, height) + (1.0 - smoothstep(0.0, 0.04, height));
	float glow = 0.16 + 0.55 * lines + 0.12 * scan + drift + 0.45 * fresnel + leading + 0.6 * rims;
	ALBEDO = color.rgb * intensity * glow * flicker;
	ALPHA = clamp(glow, 0.0, 1.0) * 0.75;
}
