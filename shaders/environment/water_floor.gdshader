shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// The hand boss arena's water: two pixelated water textures scrolling against each other, a gentle swell, and a glowing
// foam line where the water meets anything that sticks out of it. The patterns come from the brush's UVs.
// Touches (WaterRipple, scripts/environment/water_ripple.gd) move the water itself, like something dropped in it: the
// surface heaves in rings that spread out (they bend the lighting, so the rings catch the light as they roll, and they
// push the texture about as if the water under it were being displaced), with a faint glow on the crests. A light
// swell keeps the surface slowly shifting the rest of the time.

uniform vec3 albedo : source_color = vec3(1.0);
uniform sampler2D water_texture1 : source_color, filter_nearest, repeat_enable;
uniform sampler2D water_texture2 : source_color, filter_nearest, repeat_enable;
uniform sampler2D noise_texture : repeat_enable;
uniform vec2 scroll_speed1 = vec2(0.05, 0.0);
uniform vec2 scroll_speed2 = vec2(-0.03, 0.0);
uniform float blend_factor = 0.5;
uniform vec2 scale1 = vec2(1.0, 1.0);
uniform vec2 scale2 = vec2(1.0, 1.0);
uniform float wave_strength = 1.0;
uniform float wave_scale = 0.02;
uniform int pixelation_level = 64;
uniform float FoamSize = 0.5;
uniform sampler2D DepthTexture : hint_depth_texture;
uniform float WaterOpacity = 1.0;
uniform float FoamGlowIntensity = 0.5;

// Rings spreading out from where something touched the water. Set from code by WaterRipple: each is (world x, world z,
// age in seconds, strength). The script fades the strength out over the ripple's life; zero strength is an empty slot.
const int MAX_RIPPLES = 4;
uniform vec4 touch_ripples[MAX_RIPPLES];
uniform float ripple_speed = 9.0;          // meters per second
uniform float ripple_wavelength = 2.4;     // meters between rings
uniform float ripple_train = 14.0;         // how far behind the front rings still show, meters
uniform vec3 ripple_color : source_color = vec3(0.55, 1.0, 1.0);
uniform float ripple_bend = 1.1;           // how strongly rings tilt the surface (the lighting)
uniform float ripple_push = 0.03;          // how far rings push the water's texture about, in texture widths
uniform float ripple_glow = 0.35;          // glow on the crests
uniform float swell_strength = 0.0;       // the always-on shifting of the surface
uniform vec3 line_color : source_color = vec3(0.25, 0.9, 1.0);   // the bright lines of the texture glow this colour
uniform float line_glow = 0.0;

varying vec3 world_pos;

void vertex() {
	vec2 global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float noise_value = texture(noise_texture, global_position * wave_scale).r;
	float wave = sin(global_position.x * 0.2 + global_position.y * 0.2 + TIME + noise_value * 10.0) * wave_strength;
	VERTEX.y += wave;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Rings from touches: a train of waves behind each expanding front, fading with age and distance. `slope` is how the
	// surface tilts there; `heave` is how high it is lifted (crests positive).
	vec2 slope = vec2(0.0);
	float heave = 0.0;
	float crest_glow = 0.0;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 ripple = touch_ripples[i];
		if (ripple.z < 0.0 || ripple.w <= 0.0) {
			continue;
		}
		vec2 offset = world_pos.xz - ripple.xy;
		float dist = length(offset);
		float behind = ripple.z * ripple_speed - dist;   // how far inside the front this point is
		if (behind <= 0.0 || behind > ripple_train) {
			continue;
		}
		float fade = 1.0 - behind / ripple_train;
		fade *= ripple.w / (1.0 + dist * 0.012) * smoothstep(0.0, ripple_wavelength * 0.5, behind);
		float wave_phase = behind / ripple_wavelength * 6.2832;
		vec2 outward = dist > 0.001 ? offset / dist : vec2(0.0);
		slope += outward * cos(wave_phase) * fade;
		heave += sin(wave_phase) * fade;
		crest_glow += pow(max(sin(wave_phase), 0.0), 3.0) * fade;
	}
	float ring_tilt = length(slope);                    // from the rings alone (the swell is added below)
	// The swell: two slow noise layers drifting across each other tilt the surface a little
	vec2 swell_uv = world_pos.xz * 0.05;
	float n1 = texture(noise_texture, swell_uv + vec2(TIME * 0.02, 0.0)).r;
	float n2 = texture(noise_texture, swell_uv * 1.7 - vec2(0.0, TIME * 0.03)).r;
	float n1x = texture(noise_texture, swell_uv + vec2(0.01 + TIME * 0.02, 0.0)).r;
	float n2y = texture(noise_texture, swell_uv * 1.7 + vec2(0.0, 0.01 - TIME * 0.03)).r;
	slope += vec2(n1x - n1, n2y - n2) * 14.0 * swell_strength;

	// The water's texture is pushed about by the heaving surface
	vec2 push = (slope * 0.6 + vec2(heave) * 0.4) * ripple_push;
	vec2 scaledUV1 = UV * scale1;
	vec2 scaledUV2 = UV * scale2;
	vec2 scrolledUV1 = scaledUV1 + scroll_speed1 * TIME + push;
	vec2 scrolledUV2 = scaledUV2 + scroll_speed2 * TIME - push;
	scrolledUV1 = mod(scrolledUV1, vec2(1.0, 1.0));
	scrolledUV2 = mod(scrolledUV2, vec2(1.0, 1.0));
	scrolledUV1 = floor(scrolledUV1 * float(pixelation_level)) / float(pixelation_level);
	scrolledUV2 = floor(scrolledUV2 * float(pixelation_level)) / float(pixelation_level);

	vec4 water_color1 = texture(water_texture1, scrolledUV1);
	vec4 water_color2 = texture(water_texture2, scrolledUV2);
	vec4 blended_water_color = mix(water_color1, water_color2, blend_factor);

	float depthValue = texture(DepthTexture, SCREEN_UV).r;
	vec4 worldPosition = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depthValue, 1.0);
	worldPosition.xyz /= worldPosition.w;
	float foamEffect = clamp(1.0 - smoothstep(worldPosition.z + FoamSize, worldPosition.z, VERTEX.z), 0.0, 1.0);
	float foamOpacity = 1.0 - foamEffect;
	float foamEffectRounded = round(foamOpacity);
	float finalOpacity = foamEffectRounded + WaterOpacity;

	ALBEDO = blended_water_color.rgb * albedo;
	ALPHA = finalOpacity;
	// The texture's bright lines glow, so the water is dark with light lines running through it (not a bright sheet)
	float lines = smoothstep(0.66, 0.95, blended_water_color.r);
	EMISSION = vec3(foamEffectRounded) * FoamGlowIntensity + ripple_color * crest_glow * ripple_glow + line_color * lines * line_glow;
	METALLIC = 0.0;
	// Disturbed water is smoother, so the tilted surface catches the light
	ROUGHNESS = 1.0;
	NORMAL_MAP = normalize(vec3(-slope.x * ripple_bend, -slope.y * ripple_bend, 1.0)) * 0.5 + 0.5;
}
