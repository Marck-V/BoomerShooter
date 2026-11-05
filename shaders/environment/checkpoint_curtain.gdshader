shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A checkpoint's curtain: a see-through sheet of thin neon scanlines filling a corridor, drifting down like a
// scanner, with a bright frame where it meets the walls. When the player walks through it the lines flash, a ripple
// runs out from where they crossed, and it turns to the reached colour and dims.
// Drawn on a quad filling the corridor (UV 0..1); `size` must match the quad, in meters.

uniform vec3 idle_color : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 reached_color : source_color = vec3(0.3, 1.0, 0.4);
uniform vec2 size = vec2(4.0, 4.0);
uniform float reached : hint_range(0.0, 1.0) = 0.0;     // 0 = waiting for the player, 1 = reached
uniform float flash : hint_range(0.0, 4.0) = 0.0;
uniform vec2 ripple_center = vec2(0.5);                 // UV of where the player crossed
uniform float ripple_radius = -1.0;                     // meters; below zero = no ripple
uniform float line_spacing = 0.14;                      // meters between scanlines
uniform float scroll_speed = 0.3;                       // meters per second
uniform float intensity : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec2 p = UV * size;   // meters across, down from the top

	// The ripple: a ring growing out from the crossing point that bends the lines and lights them up as it passes
	float ring = 0.0;
	if (ripple_radius >= 0.0) {
		float d = distance(p, ripple_center * size);
		float fade = 1.0 - smoothstep(0.0, max(size.x, size.y), ripple_radius);
		ring = (1.0 - smoothstep(0.0, 0.4, abs(d - ripple_radius))) * fade;
	}

	float y = p.y - TIME * scroll_speed + ring * 0.1;
	float t = fract(y / line_spacing);
	float line = 1.0 - smoothstep(0.0, 0.22, abs(t - 0.5) * 2.0);
	// A brighter band sweeping down over the lines every couple of seconds
	float sweep = pow(0.5 + 0.5 * sin(p.y * 1.3 - TIME * 2.2), 10.0);
	// A little flicker, different on every line, so it feels like a projection
	float row = floor(y / line_spacing);
	float flicker = 0.85 + 0.15 * sin(TIME * 13.0 + row * 7.31);

	float edge_distance = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	float frame = 1.0 - smoothstep(0.0, 0.1, edge_distance);
	float haze = exp(-edge_distance * 2.5) * 0.25;

	float lines = line * (0.28 + 0.6 * sweep) * flicker * mix(1.0, 0.2, reached);
	float amount = lines + (frame * 0.9 + haze) * mix(1.0, 0.45, reached) + ring * 0.9 + flash * (0.15 + line * 0.6);

	vec3 col = mix(idle_color, reached_color, reached);
	col = mix(col, vec3(1.0), clamp(flash * 0.5 + ring * 0.4, 0.0, 0.8));
	ALBEDO = col * 1.8;   // over 1.0 so the glow effect picks it up
	ALPHA = clamp(amount * intensity, 0.0, 1.0);
}
