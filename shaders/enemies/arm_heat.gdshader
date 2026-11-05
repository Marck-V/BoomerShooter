shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Drawn on a second copy of the enemy's skinned mesh: the arm heats up from the knuckles towards the elbow as a
// parryable punch charges. Everything further than radius from the fist-to-elbow line stays dark.

uniform vec3 fist_point;
uniform vec3 elbow_point;
uniform float reach : hint_range(0.0, 1.0) = 0.2;     // how far up the arm the heat has climbed
uniform float radius = 0.16;
uniform float intensity = 0.0;
uniform vec3 hot_color : source_color = vec3(1.0, 0.85, 0.3);
uniform vec3 cool_color : source_color = vec3(1.0, 0.4, 0.02);

varying vec3 world_position;

void vertex() {
	VERTEX += NORMAL * 0.004;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 arm = elbow_point - fist_point;
	float along = clamp(dot(world_position - fist_point, arm) / max(dot(arm, arm), 0.0001), 0.0, 1.0);
	float away = distance(world_position, fist_point + arm * along);
	float near_arm = 1.0 - smoothstep(radius * 0.6, radius, away);
	float heat = 1.0 - smoothstep(reach * 0.35, max(reach, 0.01), along);
	float shimmer = 0.85 + 0.15 * sin(TIME * 18.0 + world_position.y * 40.0);
	ALBEDO = mix(cool_color, hot_color, heat) * 2.0;
	ALPHA = clamp(near_arm * heat * intensity * shimmer, 0.0, 1.0);
}
