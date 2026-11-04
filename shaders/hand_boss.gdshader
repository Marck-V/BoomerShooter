shader_type spatial;
render_mode cull_disabled;

// The hand boss's skin: the vertex colours from tools/assetgen/hand_boss.py, glossy, plus two things the fight
// needs. clip_plane cuts away everything past the portal the forearm comes out of, so the hand can emerge from it
// and be pulled back in; near the portal the arm fades to black, as if still in the dark dimension behind it. glow_color / glow_amount light the whole hand up
// (charging an attack, open to crits, phase changes).
// Two-sided, so looking into the cut shows the inside of the arm rather than nothing.

uniform float metallic_value = 0.35;
uniform float roughness_value = 0.32;
uniform vec4 clip_plane = vec4(0.0, 1.0, 0.0, 100000.0);  // drop points where dot(world, xyz) > w
uniform vec3 portal_glow_color : source_color = vec3(0.6, 0.12, 1.0);
uniform float portal_shadow_depth = 7.0;                  // meters from the cut that fade into the dark
uniform float portal_line_depth = 0.25;                   // the thin violet line right at the cut
uniform vec3 glow_color : source_color = vec3(1.0, 0.8, 0.2);
uniform float glow_amount = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float past = dot(world_position, clip_plane.xyz) - clip_plane.w;
	if (past > 0.0) {
		discard;
	}
	// Coming out of the dark: the arm is black where it leaves the portal and gets its colour back further out
	float shadow = 1.0 - clamp(-past / portal_shadow_depth, 0.0, 1.0);
	shadow = shadow * shadow * (3.0 - 2.0 * shadow);
	ALBEDO = COLOR.rgb * (1.0 - shadow);
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5 * (1.0 - shadow);
	float line = exp(past / portal_line_depth);
	EMISSION = (glow_color * glow_amount) * (1.0 - shadow) + portal_glow_color * line * 1.8;
}
