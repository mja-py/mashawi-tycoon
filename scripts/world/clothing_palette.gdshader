shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 target_hsv;
uniform float reference_value = 0.30;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 0.000001)), d / (q.x + 0.000001), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 source = texture(atlas, UV).rgb;
	vec3 hsv = rgb_to_hsv(pow(max(source, vec3(0.0)), vec3(1.0 / 2.2)));
	float warm = max(1.0 - smoothstep(0.13, 0.20, hsv.x), smoothstep(0.96, 0.99, hsv.x));
	float skin_or_trim = warm * smoothstep(0.18, 0.30, hsv.y);
	float cloth = smoothstep(0.70, 0.78, hsv.x) * (1.0 - skin_or_trim);
	vec3 tint = hsv_to_rgb(vec3(target_hsv.xy, clamp(hsv.z * target_hsv.z / reference_value, 0.0, 1.0)));
	// Skin, eyes, hair, embroidery and shoes retain their original albedo.
	ALBEDO = mix(source, pow(tint, vec3(2.2)), cloth);
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
