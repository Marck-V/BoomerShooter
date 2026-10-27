shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// Aura shell for the glowing fist of a parryable attack. Only the rim of the sphere lights up, so the fist
// inside stays visible: the centre is fully transparent and the glow builds towards the silhouette.

uniform vec3 aura_color : source_color = vec3(1.0, 0.75, 0.15);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float rim_power : hint_range(0.5, 6.0) = 2.0;     // higher = thinner, tighter rim
uniform float flicker_speed = 16.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.25;
uniform float phase = 0.0;                                  // per-shell offset so the shells don't pulse together

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	// Slow shimmer moving up the sphere, so it reads as a living aura and not a static shell
	float shimmer = 1.0 - flicker_amount + flicker_amount * sin(TIME * flicker_speed + phase + UV.y * 9.0);
	float amount = clamp(rim * intensity * shimmer, 0.0, 1.0);
	ALBEDO = aura_color * 1.6;   // over 1.0 so the glow effect picks it up
	ALPHA = amount;
}
