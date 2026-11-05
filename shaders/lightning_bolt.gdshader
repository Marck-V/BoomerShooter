// Every bolt of lightning in the game (scripts/weapons/lightning_bolt.gd builds the ribbons): a thin near-white core
// with a soft glow round it, blue near the core and violet at the edges.
// The ribbon's UV.y runs 0 to 1 across its width; its vertex alpha fades a bolt out along its length (tapered ends,
// branches dying away). Additive and unshaded, so bolts never need sorting.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 core_color : source_color = vec3(0.92, 0.96, 1.0);
uniform vec3 inner_color : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 outer_color : source_color = vec3(0.55, 0.28, 1.0);
uniform float core_size = 0.16;         // share of the ribbon's half-width that is the white core
uniform float energy = 5.0;             // over 1 so it blooms
uniform float intensity = 1.0;          // the script strobes this

void fragment() {
	float d = abs(UV.y * 2.0 - 1.0);                      // 0 on the centre line, 1 at the ribbon's edge
	float core = 1.0 - smoothstep(core_size * 0.5, core_size, d);
	float glow = exp(-d * d * 5.0) * (1.0 - d);           // soft, and exactly 0 at the edge so there's no seam
	vec3 halo = mix(outer_color, inner_color, glow);
	vec3 colour = core_color * core * 1.8 + halo * glow;
	ALBEDO = colour * energy * intensity * COLOR.a;
}
