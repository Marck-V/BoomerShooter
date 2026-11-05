shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

const int MAX_HITS = 8;

uniform vec3 hit_points[8];
uniform int hit_count = 0;
uniform float radius = 0.4;
uniform float intensity = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	VERTEX += NORMAL * 0.003;
}

void fragment() {
	float falloff = 0.0;
	for (int i = 0; i < MAX_HITS; i++) {
		if (i >= hit_count) {
			break;
		}
		falloff = max(falloff, smoothstep(radius, 0.0, distance(local_pos, hit_points[i])));
	}
	ALBEDO = flash_color.rgb * 2.0;
	ALPHA = falloff * intensity;
}
