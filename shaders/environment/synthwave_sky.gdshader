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
uniform float star_size : hint_range(0.005, 0.04) = 0.013;       // how far the biggest star's points reach, in radians
uniform float star_arm_width : hint_range(0.0005, 0.01) = 0.0015; // half the thickness of a point at its base, in radians
uniform float star_shimmer : hint_range(0.0, 0.5) = 0.15;       // how much the points grow and shrink as a star twinkles
uniform vec2 star_shimmer_speed = vec2(0.25, 0.7);             // twinkles per second, min and max

// The sky is split into cells of about the same size and each star stays fully inside its own, so two stars can
// never overlap. star_size must stay under half a cell (0.05 radians) divided by the 1.265 of the biggest swell.
const float STAR_CELLS_PER_RADIAN = 10.0;
const float STAR_CHANCE = 0.7;              // chance that a cell has a star
const float STAR_MIN_ROW_CELLS = 6.0;       // rows with fewer cells than this ring the zenith too tightly to hold a star

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// A small diamond with four thin arms along the axes, 1 in the middle. The arms narrow and fade out toward the
// tips. They never get thinner than the retro filter's chunky pixels can show, so they don't break up into dots.
float star_shape(vec2 offset, float reach, float arm_width) {
	vec2 along = abs(offset) / reach;
	float diamond = 1.0 - smoothstep(0.12, 0.3, along.x + along.y);
	float fade_x = clamp(1.0 - along.x, 0.0, 1.0);
	float fade_y = clamp(1.0 - along.y, 0.0, 1.0);
	float arm_x = fade_x * fade_x * (1.0 - smoothstep(0.5, 1.0, abs(offset.y) / (arm_width * mix(0.55, 1.0, fade_x))));
	float arm_y = fade_y * fade_y * (1.0 - smoothstep(0.5, 1.0, abs(offset.x) / (arm_width * mix(0.55, 1.0, fade_y))));
	return max(diamond, max(arm_x, arm_y));
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
	// are glowing keeps drifting around the sky. The rest keep a steady brightness. Every star is a diamond with
	// four tapered points and shorter diagonal rays, and its points shimmer in and out at their own quicker pace.
	float star_light = 0.0;
	// Rows of cells, with fewer cells in the rows near the zenith so they all keep their width. Each row is slid
	// sideways by its own amount so the cells don't line up into a visible grid.
	float star_row = floor(elevation * STAR_CELLS_PER_RADIAN);
	float row_elevation = (star_row + 0.5) / STAR_CELLS_PER_RADIAN;
	float row_cells = max(round(6.2831853 * cos(row_elevation) * STAR_CELLS_PER_RADIAN), 1.0);
	float row_slide = hash21(vec2(star_row, 7.1)) * row_cells;
	float row_pos = (azimuth / 6.2831853 + 0.5) * row_cells + row_slide;
	vec2 c = vec2(mod(floor(row_pos), row_cells), star_row);
	if (row_cells >= STAR_MIN_ROW_CELLS && hash21(c) < STAR_CHANCE) {
		float seed_phase = hash21(c + vec2(17.3, 5.1));
		float seed_speed = hash21(c + vec2(91.7, 33.9));
		float twinkles = step(0.5, hash21(c + vec2(3.7, 61.3)));
		float swell = 0.5 + 0.5 * sin(TIME * mix(star_swell_speed.x, star_swell_speed.y, seed_speed) * 6.2831853 + seed_phase * 6.2831853);
		swell = smoothstep(0.1, 0.9, swell) * twinkles;
		float seed_size = hash21(c + vec2(47.9, 12.6));
		float seed_shimmer = hash21(c + vec2(71.3, 88.2));
		float shimmer = sin(TIME * mix(star_shimmer_speed.x, star_shimmer_speed.y, seed_speed) * 6.2831853 + seed_shimmer * 6.2831853);

		// Mostly small stars, with the odd big one
		float base_reach = star_size * mix(0.5, 1.0, seed_size * seed_size * seed_size);
		float reach = base_reach * mix(0.8, 1.1, swell) * (1.0 + shimmer * star_shimmer);

		// A star wanders as far from its cell's centre as its size allows at its biggest, so the points stay inside
		float room = max(0.5 - base_reach * 1.265 * STAR_CELLS_PER_RADIAN, 0.0);
		vec2 jitter = (vec2(hash21(c + vec2(29.1, 73.4)), hash21(c + vec2(64.2, 19.8))) * 2.0 - 1.0) * room;
		// Measured on a plane touching the sky at the star, so its shape stays true however high up it is
		float star_azimuth = ((floor(row_pos) + 0.5 + jitter.x - row_slide) / row_cells - 0.5) * 6.2831853;
		float star_elevation = (star_row + 0.5 + jitter.y) / STAR_CELLS_PER_RADIAN;
		vec3 star_east = vec3(cos(star_azimuth), 0.0, sin(star_azimuth));
		vec3 star_north = vec3(-sin(star_azimuth) * sin(star_elevation), cos(star_elevation), cos(star_azimuth) * sin(star_elevation));
		vec2 offset = vec2(dot(dir, star_east), dot(dir, star_north));

		// Rotating by 45 degrees turns the same shape into the shorter diagonal rays
		vec2 diagonal = vec2(offset.x + offset.y, offset.x - offset.y) * 0.7071;
		float shape = max(star_shape(offset, reach, star_arm_width), star_shape(diagonal, reach * 0.5, star_arm_width) * 0.5);

		// Steady stars stay at 1.0, swelling ones go between star_rest and 1.0 + star_glow
		star_light += shape * mix(1.0, mix(star_rest, 1.0 + star_glow, swell), twinkles);

		// A faint halo around a star that is near the peak of its swell
		star_light += swell * swell * star_halo * (1.0 - smoothstep(0.0015, 0.005, length(offset)));
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
