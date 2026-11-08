shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Warning shapes the boss paints on the floor before an attack. Two shapes on a flat plane (UV 0..1):
//   mode 0, a circle: faint danger area, a bright edge, and a fill growing from the centre with `progress`
//   mode 1, a lane (UV.y runs from the boss to the end of the lane): chevrons pointing away from the boss and rushing along it, filling with `progress`
//   mode 2, a sector fanning out from the middle of the plane along +Z, `half_angle` either side: chevrons running outward, filling with `progress`

uniform int mode = 0;
uniform vec3 color : source_color = vec3(1.0, 0.25, 0.1);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform float half_angle = 0.3;

void fragment() {
	float amount = 0.0;
	if (mode == 0) {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		if (r > 1.0) {
			discard;
		}
		float danger = 0.07;
		float edge = smoothstep(0.93, 0.985, r) * (1.0 - smoothstep(0.985, 1.0, r));
		float fill = (1.0 - smoothstep(progress - 0.03, progress, r)) * 0.24;
		// A slow pulse across the whole area, quickening as the attack gets close
		float pulse = 0.75 + 0.25 * sin(TIME * (4.0 + progress * 10.0));
		// Rings rushing inwards, so it reads as something about to come down
		float rings = smoothstep(0.7, 1.0, 0.5 + 0.5 * sin(r * 24.0 + TIME * 6.0)) * 0.12;
		amount = (danger + fill + rings) * pulse + edge * 0.9;
	} else if (mode == 2) {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float a = abs(atan(p.x, p.y));
		if (r > 1.0 || a > half_angle || p.y < 0.0) {
			discard;
		}
		// Spokes cover a lot of floor, so the inside stays faint and the outline does the work: the floor between
		// the spokes has to stay readable
		float side = 1.0 - smoothstep(0.0, 0.06, r * (half_angle - a));
		float chevron = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin((r * 18.0 + a * 4.0 - TIME * 5.0) * 3.14159));
		float fill = (1.0 - smoothstep(progress - 0.04, progress, r)) * 0.12;
		float front = (1.0 - smoothstep(0.0, 0.025, abs(r - progress))) * 0.6;   // a bright line sweeping out as it charges
		float throb = 0.8 + 0.2 * sin(TIME * (5.0 + progress * 10.0));
		amount = (0.035 + chevron * 0.08 + fill + front) * throb + side * 1.0;
		amount *= smoothstep(0.0, 0.05, r);
	} else {
		float lateral = abs(UV.x * 2.0 - 1.0);
		float along = UV.y;
		float edge = smoothstep(0.86, 0.97, lateral) * (1.0 - smoothstep(0.97, 1.0, lateral));
		float chevron = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin((along * 14.0 + lateral * 2.5 - TIME * 5.0) * 3.14159));
		float fill = (1.0 - smoothstep(progress - 0.04, progress, along)) * 0.28;
		float pulse = 0.8 + 0.2 * sin(TIME * (5.0 + progress * 10.0));
		amount = (0.09 + chevron * 0.22 + fill) * pulse + edge * 0.8;
		amount *= smoothstep(0.0, 0.04, along) * (1.0 - smoothstep(0.96, 1.0, along) * 0.6);
	}
	ALBEDO = color * 2.0;   // over 1.0 so the glow effect picks it up
	ALPHA = clamp(amount * strength, 0.0, 1.0);
}
