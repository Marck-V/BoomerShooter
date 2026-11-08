shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// The pistol while a Parry Round is ready (scripts/weapons/pistol.gd, scripts/weapons/pistol_charge_fx.gd): chaotic
// energy is packed inside the barrel at the tip, trying to escape. This is the part that shows on the barrel itself:
// thin white cracks of light crawl and flicker over the surface near the muzzle, brightest right at the tip and dying
// away towards the receiver, with irregular surges. Drawn as an additive overlay, so the gun's own textures stay
// untouched underneath. The pistol's script adds the glowing core, sparks and light at the muzzle.
//
// The model's barrel runs along +Z (the muzzle end), so the region is given in model space.

uniform float intensity : hint_range(0.0, 2.0) = 1.0;       // the pistol script ramps it in, and blinks it as the window runs out
uniform float tip_z = 1.39;                                 // model-space z of the muzzle
uniform float reach = 0.6;                                  // how far back from the tip the cracks reach
uniform vec3 glow_color : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 model_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	model_pos = VERTEX;
	// A hair off the surface so the overlay doesn't z-fight with the gun
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	// Strongest at the tip, gone by `reach` back along the barrel, all the way round it
	float back = clamp((tip_z - model_pos.z) / reach, 0.0, 1.0);
	float mask = pow(1.0 - back, 1.6);

	// Chaotic timing: the pattern jumps about 20 times a second, with a random brightness each time and the odd surge
	float tick = floor(TIME * 20.0);
	float flicker = 0.45 + 0.55 * hash13(vec3(tick, 3.7, 1.3));
	float surge = step(0.88, hash13(vec3(tick, 9.1, 5.5))) * 0.9;

	// Thin bright cracks: the lines where the noise crosses the middle, at two scales, shifting every tick
	vec3 jump = vec3(hash13(vec3(tick, 1.0, 0.0)), hash13(vec3(tick, 2.0, 0.0)), hash13(vec3(tick, 3.0, 0.0))) * 5.0;
	float n1 = value_noise(model_pos * 10.0 + jump + vec3(0.0, 0.0, -TIME * 9.0));
	float n2 = value_noise(model_pos * 23.0 - jump);
	float cracks = (1.0 - smoothstep(0.0, 0.06, abs(n1 - 0.5))) * 1.3
			+ (1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5))) * 0.8;

	// A steady hot fill right at the tip, so it reads as light pressing out from inside
	float fill = pow(1.0 - back, 5.0) * 0.55;

	float energy = mask * (cracks + fill) * (flicker + surge);
	ALBEDO = glow_color * energy * intensity * 2.0;
}
