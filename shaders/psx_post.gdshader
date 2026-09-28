shader_type canvas_item;

uniform sampler2D screen_texture : source_color, hint_screen_texture, repeat_disable, filter_nearest;

uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;

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
uniform float dither_strength : hint_range(0.0, 1.0) = 0.3;

float hashOld12(vec2 p){
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453 + (sin((TIME)) / noise_time_fac)) ;
}

vec3 color_mix(vec3 a, vec3 b, float f ){
	f = clamp(abs(f), 0,1);
	float invf = 1.0 - f;
	return (a*f) + (b*invf);
}

vec3 quantize_color(vec3 color, int levels) {
	float quantizer = float(levels - 1);
	return floor(color * quantizer + 0.5) / quantizer;
}

float dither(vec2 position, float brightness) {
	int x = int(mod(position.x, 4.0));
	int y = int(mod(position.y, 4.0));
	int index = x + y * 4;
	float dithering[16] = float[](
		0.0, 0.5, 0.125, 0.625,
		0.75, 0.25, 0.875, 0.375,
		0.1875, 0.6875, 0.0625, 0.5625,
		0.9375, 0.4375, 1.0, 0.8125
	);
	float threshold = dithering[index];
	return brightness < threshold ? 0.0 : 1.0;
}

void fragment(){
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	// effect_strength == 0 must look exactly like this overlay isn't here at
	// all. No early return (not legal inside fragment() in Godot's shading
	// language) -- gated with if/else instead.
	if (effect_strength <= 0.0) {
		COLOR = vec4(screen_color, 0.8);
	} else {
		vec2 screen_coords = SCREEN_UV * 2.0 - 1.0;

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

		float base_lum = dot(screen_color, vec3(0.299, 0.587, 0.114));
		bool is_bright = base_lum > 0.92;

		if (is_bright) {
			// Bright VFX (lightning, etc.) left completely untouched -- this
			// threshold used to be 0.25, tuned back when this shader ran
			// BEFORE Glow/Tonemap. Now that it runs after the frame is fully
			// composited, everything is in normal tonemapped 0-1 range, so
			// 0.25 caught ordinary bright-ish surfaces (skin tones, weapon
			// metal) too. Raised so only genuine near-white VFX bypasses it.
			COLOR = vec4(screen_color, 0.8);
		} else {
			vec3 final_color = screen_color;

			if (enable_noise){
				vec3 twocolornoise = color_mix(fog_color, noise_color, hashOld12(screen_coords));
				final_color = color_mix(twocolornoise, final_color, depth_mask_inv);
			}

			if (enable_fog){
				final_color = color_mix(fog_color, final_color, depth_mask_inv);
			}

			if (enable_color_limitation){
				final_color = quantize_color(final_color, color_levels);
			}

			if (enable_dithering){
				float brightness = dot(final_color, vec3(0.3, 0.59, 0.11));
				brightness += dither_strength * (dither(FRAGCOORD.xy, brightness) - 0.5);
				final_color *= (1.0 + dither_strength * (dither(FRAGCOORD.xy, brightness) - 0.5));
			}

			// Blend toward the untouched frame as strength drops, so 0 = no
			// effect and 1 = the full look this shader was tuned for.
			final_color = mix(screen_color, final_color, effect_strength);

			COLOR = vec4(final_color, 0.8);
		}
	}
}
