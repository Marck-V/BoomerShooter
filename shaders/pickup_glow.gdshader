shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float intensity = 0.8;
uniform float pulse_speed = 2.0;

void vertex() {
	// Billboard: always face the camera, keep the node's position
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float falloff = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	float pulse = 0.85 + 0.15 * sin(TIME * pulse_speed);
	ALBEDO = glow_color.rgb * intensity * pulse;
	ALPHA = falloff;
}
