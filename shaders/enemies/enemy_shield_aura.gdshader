shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled;

// The enemy shield: a thin flickering shell just outside the body, drawn on a second copy of the enemy's mesh (see
// scripts/enemies/shield.gd). It draws nothing over the body itself, so the enemy and the glow of a parryable attack
// stay completely clear. `heat` is how close the shield is to breaking (0 fresh, 1 about to go): the shell thickens, its
// flames lick higher and faster, and the colour runs cyan, violet, hot magenta and white, with a throb that ends in a
// strobe. `hit` flares it when the shield is hit, and `burst` blows it outward as it breaks.

#include "res://shaders/enemies/shield_heat.gdshaderinc"

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float hit : hint_range(0.0, 1.0) = 0.0;
uniform float burst : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;

void vertex() {
	VERTEX += NORMAL * (0.02 + heat * 0.06 + hit * 0.03 + burst * 0.4);
	local_pos = VERTEX;
}

void fragment() {
	float rise = TIME * (0.8 + heat * 3.5);
	float flame = noise3(local_pos * vec3(5.0, 2.5, 5.0) + vec3(0.0, -rise, 0.0));
	float flame2 = noise3(local_pos * vec3(11.0, 5.0, 11.0) + vec3(3.0, -rise * 1.7, 1.0));
	float body = mix(flame, flame2, 0.4);
	float amount = smoothstep(mix(0.55, 0.2, heat), 0.95, body) * 0.9 + 0.12;
	amount = amount * heat_pulse(heat, TIME) + hit * 0.7;
	amount = mix(amount, 1.0, burst * 0.6) * (1.0 - burst);
	vec3 colour = mix(heat_color(heat), vec3(1.0, 0.95, 0.95), max(hit * 0.6, burst));
	ALBEDO = colour * 2.0;
	ALPHA = clamp(amount, 0.0, 1.0);
}
