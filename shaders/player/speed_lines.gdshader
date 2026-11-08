shader_type canvas_item;

// Speed lines drawn over the whole screen (set up in scripts/player/player.gd), under the HUD. Two looks:
//   radial   (vertical = 0): thin white lines flying out from the middle of the screen, the clear middle left alone.
//            Used for the dash.
//   vertical (vertical = 1): cyan-white streaks rushing up the screen, thickest towards the sides, like the world
//            tearing past as the player plunges. Used for the ground slam.
// The lines are re-rolled about 20 times a second so they flicker and jump instead of sliding smoothly.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float vertical : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.78;                       // screen width / height, so the radial lines stay even
uniform vec4 radial_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 vertical_color : source_color = vec4(0.55, 0.92, 1.0, 1.0);
uniform float radial_lines = 96.0;
uniform float vertical_lines = 52.0;
uniform float clear_radius = 0.28;                 // radial: the clear middle, in screen heights from the centre

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float radial_alpha(vec2 uv, float tick) {
	vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
	float r = length(d);
	float a = atan(d.y, d.x) / TAU + 0.5;
	float cell = floor(a * radial_lines);
	float across = abs(fract(a * radial_lines) - 0.5) * 2.0;           // 0 along the line's middle, 1 at its edge
	float rnd = hash11(cell + tick * 17.0);
	float exists = step(0.5, rnd);                                      // about half the lines show at any moment
	float start = clear_radius + hash11(cell * 3.1 + tick) * 0.3;      // each starts further out than the last
	float along = smoothstep(start, start + 0.18, r);
	float width = 0.18 + 0.3 * hash11(cell * 7.7);
	float line = 1.0 - smoothstep(width * 0.4, width, across);
	return exists * along * line * (0.55 + 0.45 * hash11(cell * 1.9 + tick * 3.0));
}

float vertical_alpha(vec2 uv, float tick) {
	float cell = floor(uv.x * vertical_lines);
	float across = abs(fract(uv.x * vertical_lines) - 0.5) * 2.0;
	float exists = step(0.42, hash11(cell * 1.7 + tick * 5.0));
	float width = 0.12 + 0.25 * hash11(cell * 4.3);
	float line = 1.0 - smoothstep(width * 0.4, width, across);
	// Each column scrolls up at its own speed; its streak is a short bright dash with a soft tail
	float speed = 2.5 + 3.5 * hash11(cell * 5.3);
	float stretch = 0.5 + 1.2 * hash11(cell * 2.1);
	float v = fract(uv.y * stretch + TIME * speed + hash11(cell * 9.7));
	float streak = smoothstep(0.0, 0.03, v) * (1.0 - smoothstep(0.1, 0.5, v));
	// Thickest at the sides, with a few across the middle
	float edge = smoothstep(0.1, 0.65, abs(uv.x - 0.5) * 2.0);
	return exists * line * streak * (0.3 + 0.7 * edge);
}

void fragment() {
	float tick = floor(TIME * 20.0);
	float alpha = mix(radial_alpha(UV, tick), vertical_alpha(UV, tick), vertical);
	vec4 color = mix(radial_color, vertical_color, vertical);
	COLOR = vec4(color.rgb, clamp(alpha * intensity, 0.0, 1.0) * color.a);
}
