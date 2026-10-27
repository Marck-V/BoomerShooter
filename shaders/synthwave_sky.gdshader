shader_type sky;

// Retro sunset sky: posterized color bands, a striped sun, a few stars.
// The direction is snapped to a coarse grid so the sky is made of visible chunky pixels.

uniform vec3 sun_direction = vec3(-0.3, 0.12, -1.0);
uniform float sun_radius : hint_range(0.02, 0.6) = 0.2;     // radians
uniform float pixels_per_radian : hint_range(20.0, 400.0) = 95.0;
uniform int bands : hint_range(3, 40) = 16;

uniform vec3 top_color : source_color = vec3(0.05, 0.0, 0.22);
uniform vec3 upper_color : source_color = vec3(0.42, 0.03, 0.5);
uniform vec3 middle_color : source_color = vec3(0.9, 0.1, 0.4);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.5, 0.12);
uniform vec3 below_color : source_color = vec3(0.12, 0.0, 0.25);

uniform vec3 sun_top_color : source_color = vec3(1.0, 0.85, 0.1);
uniform vec3 sun_bottom_color : source_color = vec3(1.0, 0.25, 0.4);
uniform float sun_stripes : hint_range(2.0, 20.0) = 9.0;

uniform float star_rest : hint_range(0.0, 1.0) = 0.55;          // brightness of a swelling star at rest
uniform float star_glow : hint_range(0.0, 4.0) = 0.9;           // extra brightness at the peak of a star's swell
uniform float star_halo : hint_range(0.0, 1.0) = 0.35;          // soft halo around a star at its peak
uniform vec2 star_swell_speed = vec2(0.08, 0.2);               // swells per second, min and max (5 to 12 s each)

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// Quantize to a pixel grid in azimuth/elevation
	float azimuth = atan(dir.x, -dir.z);
	float elevation = asin(clamp(dir.y, -1.0, 1.0));
	float qa = (floor(azimuth * pixels_per_radian) + 0.5) / pixels_per_radian;
	float qe = (floor(elevation * pixels_per_radian) + 0.5) / pixels_per_radian;
	vec3 qdir = vec3(sin(qa) * cos(qe), sin(qe), -cos(qa) * cos(qe));

	// Gradient from the horizon up, in hard bands
	float height = pow(clamp(qe / 1.1, 0.0, 1.0), 0.6);   // compress the bands toward the horizon
	float stepped = floor(height * float(bands)) / float(bands);
	vec3 color;
	if (qe < 0.0) {
		color = mix(horizon_color, below_color, clamp(-qe * 2.5, 0.0, 1.0));
	} else if (stepped < 0.12) {
		color = mix(horizon_color, middle_color, stepped / 0.12);
	} else if (stepped < 0.4) {
		color = mix(middle_color, upper_color, (stepped - 0.12) / 0.28);
	} else {
		color = mix(upper_color, top_color, (stepped - 0.4) / 0.6);
	}

	// Stars, fading in toward the top. About half of them swell slowly and at random: each rests a little
	// dimmer, eases up to full brightness with a soft halo, and settles back at its own pace, so which stars
	// are glowing keeps drifting around the sky. The rest stay steady. Slow and subtle on purpose.
	vec2 star_pos = vec2(azimuth, elevation) * 260.0;
	vec2 cell = floor(star_pos);
	float star_light = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 c = cell + vec2(float(dx), float(dy));
			if (hash21(c) < 0.9965) {
				continue;
			}
			float seed_phase = hash21(c + vec2(17.3, 5.1));
			float seed_speed = hash21(c + vec2(91.7, 33.9));
			float twinkles = step(0.5, hash21(c + vec2(3.7, 61.3)));
			float swell = 0.5 + 0.5 * sin(TIME * mix(star_swell_speed.x, star_swell_speed.y, seed_speed) * 6.2831853 + seed_phase * 6.2831853);
			swell = smoothstep(0.1, 0.9, swell) * twinkles;
			if (dx == 0 && dy == 0) {
				// The star itself: steady stars stay at 1.0, swelling ones go between star_rest and 1.0 + star_glow
				star_light += mix(1.0, mix(star_rest, 1.0 + star_glow, swell), twinkles);
			} else {
				// A faint halo on the cells around a star that is near the peak of its swell
				float d = length(star_pos - (c + 0.5));
				star_light += swell * swell * star_halo * (1.0 - smoothstep(0.7, 2.0, d));
			}
		}
	}
	color += vec3(1.0) * star_light * smoothstep(0.25, 0.6, height);

	// Sun glow, then the striped disc
	vec3 sun = normalize(sun_direction);
	float angle = acos(clamp(dot(qdir, sun), -1.0, 1.0));
	float glow = floor(clamp(1.0 - angle / (sun_radius * 2.2), 0.0, 1.0) * 6.0) / 6.0;
	color = mix(color, horizon_color * 1.1, glow * glow * 0.55);

	if (angle < sun_radius) {
		// Position inside the disc, -1 at the bottom to +1 at the top
		float up = dot(qdir - sun * dot(qdir, sun), normalize(cross(cross(sun, vec3(0.0, 1.0, 0.0)), sun)));
		float s = clamp(up / sun_radius, -1.0, 1.0);
		vec3 sun_color = mix(sun_bottom_color, sun_top_color, floor((s * 0.5 + 0.5) * 8.0) / 8.0);
		// Dark stripes in the lower half, getting thicker toward the bottom
		float below = clamp((0.15 - s) / 1.15, 0.0, 1.0);
		bool cut = s < 0.15 && fract(-s * sun_stripes * 0.5) < below * 0.85;
		if (!cut) {
			color = sun_color;
		}
	}

	COLOR = color;
}
