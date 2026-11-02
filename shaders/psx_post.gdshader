shader_type canvas_item;

uniform sampler2D screen_texture : source_color, hint_screen_texture, repeat_disable, filter_nearest;

uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;

// Roughly how many rows of chunky pixels fill the screen. Rounded so every chunk is a whole number of real pixels.
uniform float pixel_height : hint_range(120.0, 1080.0) = 240.0;

uniform bool enable_fog = true;
uniform vec3 fog_color : source_color;
uniform vec3 noise_color : source_color;
uniform float fog_distance : hint_range(1, 6000) = 100;
uniform float fog_fade_range : hint_range(1, 6000) = 50;
uniform bool enable_noise = true;
uniform float noise_time_fac : hint_range(0.1, 10) = 4;
uniform bool enable_color_limitation = true;
uniform int color_levels : hint_range(2, 256) = 32;
uniform bool enable_dithering = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;

// Colour grade: muted colours, a slight tint and darker corners
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;

float hashOld12(vec2 p){
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453 + (sin((TIME)) / noise_time_fac)) ;
}

vec3 color_mix(vec3 a, vec3 b, float f ){
	f = clamp(abs(f), 0,1);
	float invf = 1.0 - f;
	return (a*f) + (b*invf);
}

// The dither nudges each pixel before it is rounded, which is what turns banding into a checker pattern
vec3 quantize_color(vec3 color, int levels, float dither_offset) {
	float quantizer = float(levels - 1);
	return clamp(floor(color * quantizer + 0.5 + dither_offset) / quantizer, 0.0, 1.0);
}

// 4x4 Bayer matrix, from -0.5 to 0.5
float dither(vec2 cell) {
	int x = int(mod(cell.x, 4.0));
	int y = int(mod(cell.y, 4.0));
	int index = x + y * 4;
	float dithering[16] = float[](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (dithering[index] + 0.5) / 16.0 - 0.5;
}

void fragment(){
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	vec2 screen_coords = SCREEN_UV * 2.0 - 1.0;
	vec3 output_color = screen_color;

	// effect_strength == 0 must leave the frame untouched. No early return
	// (not legal inside fragment() in Godot's shading language) -- gated with
	// an if instead.
	if (effect_strength > 0.0) {
		// Every real pixel in a chunk reads the colour from the chunk's centre
		float chunk = max(round((1.0 / SCREEN_PIXEL_SIZE.y) / pixel_height), 1.0);
		vec2 cell = floor(FRAGCOORD.xy / chunk);
		vec3 chunky_color = texture(screen_texture, (cell + 0.5) * chunk * SCREEN_PIXEL_SIZE).rgb;

		// CanvasItem shaders have no depth buffer (2D has none to read), so
		// the old distance-based fog/noise falloff can't be reproduced here.
		// This runs as a screen-space overlay drawn on top of the fully
		// composited 3D frame instead of a quad glued in front of the
		// camera, which is what lets Glow's bloom (already baked into
		// screen_color by this point) survive. fog/noise are flat
		// (non-distance-graded) as a result -- a direct trade for that fix.
		// Both are already off in the current material, so this is a no-op
		// for the current look.
		float depth_mask_inv = 1.0;

		float base_lum = dot(chunky_color, vec3(0.299, 0.587, 0.114));
		bool is_bright = base_lum > 0.92;

		vec3 final_color = chunky_color;

		// Bright VFX (lightning, etc.) keep their colour -- this threshold
		// used to be 0.25, tuned back when this shader ran BEFORE
		// Glow/Tonemap. Now that it runs after the frame is fully composited,
		// everything is in normal tonemapped 0-1 range, so 0.25 caught
		// ordinary bright-ish surfaces (skin tones, weapon metal) too. Raised
		// so only genuine near-white VFX bypasses it. They still get chunked.
		if (!is_bright) {
			final_color = mix(vec3(base_lum), final_color, saturation);
			final_color = (final_color - 0.5) * contrast + 0.5;
			final_color = clamp(final_color * tint, 0.0, 1.0);

			if (enable_noise){
				vec3 twocolornoise = color_mix(fog_color, noise_color, hashOld12(screen_coords));
				final_color = color_mix(twocolornoise, final_color, depth_mask_inv);
			}

			if (enable_fog){
				final_color = color_mix(fog_color, final_color, depth_mask_inv);
			}

			if (enable_color_limitation){
				float dither_offset = enable_dithering ? dither(cell) * dither_strength : 0.0;
				final_color = quantize_color(final_color, color_levels, dither_offset);
			}
		}

		// Blend toward the untouched frame as strength drops, so 0 = no
		// effect and 1 = the full look this shader was tuned for.
		output_color = mix(screen_color, final_color, effect_strength);
	}

	// Darkens toward the corners, on top of everything including bright VFX.
	// Has its own setting, so it applies whatever effect_strength is.
	float corner = clamp(length(screen_coords) / 1.414, 0.0, 1.0);
	output_color *= 1.0 - vignette_strength * smoothstep(0.35, 1.0, corner);

	COLOR = vec4(output_color, 1.0);
}
