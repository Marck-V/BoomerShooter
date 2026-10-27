shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// One tile of the boss's floor hazard, a square on a neon grid. While `active` is 0 it is a warning: a faint
// grid that blinks faster and fills from the edges as `progress` runs 0..1. While `active` is 1 it burns:
// a bright pulsing slab. `fade` takes the whole tile out at the end.

uniform vec3 warn_color : source_color = vec3(1.0, 0.55, 0.1);
uniform vec3 burn_color : source_color = vec3(1.0, 0.15, 0.1);
uniform float active : hint_range(0.0, 1.0) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge_dist = 1.0 - max(abs(p.x), abs(p.y));          // 0 at the border, 1 in the centre
	float border = 1.0 - smoothstep(0.0, 0.09, edge_dist);
	vec2 cell = abs(fract(UV * 4.0) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.06, min(0.5 - cell.x, 0.5 - cell.y));

	float amount;
	vec3 col;
	if (active < 0.5) {
		float blink = 0.55 + 0.45 * sin(TIME * (6.0 + progress * 22.0));
		float fill = 1.0 - smoothstep(progress - 0.08, progress, 1.0 - edge_dist);   // creeps in from the edges
		amount = border * (0.55 + 0.45 * blink) + grid * 0.18 * blink + fill * 0.28;
		col = warn_color;
	} else {
		float pulse = 0.78 + 0.22 * sin(TIME * 22.0);
		float scan = 0.85 + 0.15 * sin((UV.y + TIME * 1.4) * 40.0);
		amount = (0.5 + grid * 0.25) * pulse * scan + border * 0.5;
		col = burn_color;
	}
	ALBEDO = col * 2.2;   // over 1.0 so the glow effect picks it up
	ALPHA = clamp(amount * fade, 0.0, 1.0);
}
