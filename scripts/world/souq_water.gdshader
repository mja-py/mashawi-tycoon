shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;

varying vec2 creek_position;

void vertex() {
	creek_position = VERTEX.xz;
}

void fragment() {
	vec2 p = creek_position;
	float swell = sin(p.x * 2.4 + p.y * 2.7 + TIME * 0.62);
	float wave = sin(p.y * 23.0 + swell * 1.15 - TIME * 1.85);
	float scatter = sin(p.x * 6.9 + p.y * 7.6 + swell * 2.0 + TIME * 0.31);
	float ripple = smoothstep(0.78, 1.0, wave) * smoothstep(0.28, 0.95, scatter);
	vec3 channel = mix(vec3(0.062, 0.32, 0.36), vec3(0.23, 0.53, 0.51), smoothstep(3.0, 6.85, p.y));
	ALBEDO = channel + vec3(0.14, 0.15, 0.14) * ripple + vec3(0.018, 0.025, 0.029) * swell;
}
