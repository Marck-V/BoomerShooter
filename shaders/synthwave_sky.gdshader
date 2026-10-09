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

	// Stars, fading in toward the top
	vec2 cell = floor(vec2(azimuth, elevation) * 260.0);
	float star = step(0.9965, hash21(cell));
	color += vec3(1.0) * star * smoothstep(0.25, 0.6, height);

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
