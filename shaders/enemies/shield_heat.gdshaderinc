// Shared by the enemy shield concepts. heat runs from 0 (a fresh shield) to 1 (about to blow up).

// Cyan when cool, through violet and hot magenta-red, to white-hot at the very end. The enemies are orange, so the
// palette stays off orange and yellow: those would vanish against the body.
vec3 heat_color(float h) {
	vec3 c = mix(vec3(0.1, 0.85, 1.0), vec3(0.6, 0.3, 1.0), smoothstep(0.0, 0.4, h));
	c = mix(c, vec3(1.0, 0.1, 0.4), smoothstep(0.4, 0.78, h));
	return mix(c, vec3(1.0, 0.95, 0.95), smoothstep(0.9, 1.0, h));
}

// A throb that gets faster and deeper as the shield heats: slow breathing at first, a frantic strobe at the end
float heat_pulse(float h, float t) {
	float speed = mix(1.5, 22.0, h * h);
	return 1.0 - mix(0.15, 0.5, h) * (0.5 + 0.5 * sin(t * speed));
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
