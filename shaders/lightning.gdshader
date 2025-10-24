shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform vec4 lightning_color : source_color = vec4(0.5, 0.9, 1.5, 1.0);
uniform float glow_strength = 25.0;
uniform float intensity_boost = 5.0;
uniform float flicker_speed = 30.0;
uniform float noise_scale = 10.0;

void fragment() {
    // Use world-space position instead of UV to create variation along the line
    float n = sin(VERTEX.z * noise_scale + TIME * flicker_speed)
            + sin(VERTEX.x * noise_scale * 0.5 + TIME * flicker_speed * 1.3);
    float flicker = 0.6 + 0.4 * n;

    vec3 color = lightning_color.rgb * vec3(1.2, 1.1, 1.0);
    ALBEDO = color;
    EMISSION = color * glow_strength * intensity_boost * flicker;
}
