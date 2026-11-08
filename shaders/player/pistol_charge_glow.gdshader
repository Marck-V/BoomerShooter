shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// The pistol while a Parry Round is ready (scripts/weapons/pistol.gd): energy is stored along the top of the barrel,
// white, waiting to be released by the next shot. Drawn as an additive overlay on the gun, so the gun's own textures
// stay untouched underneath. The glow only covers the upward-facing surface of the barrel, fades out towards both ends,
// breathes slowly, and a soft band of brightness drifts along it towards the muzzle like charge gathering there.
//
// The model's barrel runs along +Z (the muzzle end), so the region is given in model space.

uniform float intensity : hint_range(0.0, 2.0) = 1.0;       // the pistol script ramps it in, and blinks it as the window runs out
uniform float top_y = 0.2;                                  // lowest model-space height that still counts as the barrel's top
uniform float barrel_start_z = 0.45;                        // the glow begins here, along the barrel
uniform float barrel_end_z = 1.38;                          // ... and has faded out by here (the muzzle)
uniform vec3 glow_color : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 model_pos;
varying vec3 model_normal;

void vertex() {
	model_pos = VERTEX;
	model_normal = NORMAL;
	// A hair off the surface so the overlay doesn't z-fight with the gun
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	// Only the surface that faces up
	float facing_up = smoothstep(0.1, 0.6, model_normal.y);
	// Only the top of the barrel, not the body below it
	float height = smoothstep(top_y - 0.04, top_y + 0.06, model_pos.y);
	// Fades in after the receiver and out before the muzzle
	float run = smoothstep(barrel_start_z, barrel_start_z + 0.2, model_pos.z)
			* (1.0 - smoothstep(barrel_end_z - 0.25, barrel_end_z, model_pos.z));

	float mask = facing_up * height * run;

	float breathe = 0.7 + 0.3 * sin(TIME * 5.0);
	// A soft band of extra brightness drifting towards the muzzle
	float drift = 0.5 + 0.5 * sin(model_pos.z * 7.0 - TIME * 6.0);
	float energy = breathe * (0.65 + 0.35 * drift);

	ALBEDO = glow_color * mask * energy * intensity * 2.2;
}
