shader_type spatial;
render_mode unshaded, shadows_disabled;

// Core of an energy ball: saturated at the silhouette, so the ball reads as its colour, and white-hot where the
// surface faces the camera.

uniform vec3 edge_color : source_color = vec3(1.0, 0.8, 0.05);
uniform vec3 center_color : source_color = vec3(1.0, 1.0, 0.8);
uniform float center_power : hint_range(0.5, 12.0) = 5.0;   // higher = smaller hot spot
uniform float brightness = 1.3;                              // over 1.0 so the glow effect picks it up

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = mix(edge_color, center_color, pow(facing, center_power)) * brightness;
}
