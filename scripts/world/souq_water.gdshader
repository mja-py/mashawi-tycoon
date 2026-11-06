shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;

uniform bool beach = false;
uniform float shore_edge = 7.0;
uniform vec4 sand : source_color = vec4(0.812, 0.714, 0.557, 1.0);
uniform vec4 deep : source_color = vec4(0.073, 0.36, 0.44, 1.0);
uniform vec4 shallow : source_color = vec4(0.25, 0.58, 0.55, 1.0);
uniform vec4 foam_tone : source_color = vec4(0.79, 0.89, 0.79, 1.0);
varying vec2 coast_position;

void vertex() {
	coast_position = VERTEX.xz;
}

void fragment() {
	vec2 p = coast_position;
	float swell = sin(p.x * 1.85 + p.y * 2.7 + TIME * 0.65);
	float drift = sin(p.x * 3.6 - p.y * 4.2 + TIME * 0.43);
	float weave = sin(p.y * 14.5 + swell * 2.6 + drift * 0.49 - TIME * 1.6);
	float glint = smoothstep(0.79, 0.98, weave) *
		smoothstep(0.04, 0.88, sin(p.x * 6.7 + p.y * 3.9 + swell + TIME * 0.3)) *
		(0.42 + 0.58 * smoothstep(-0.38, 0.9, drift));
	float distance_from_shore = shore_edge - p.y;
	vec3 water = mix(shallow.rgb, deep.rgb, smoothstep(0.14, 4.6, distance_from_shore));
	water += vec3(0.012, 0.024, 0.027) * (swell + drift * 0.37);
	water = mix(water, foam_tone.rgb, glint * 0.19);
	if (beach) {
		float curve = sin(p.x * 0.72) * 0.14 + sin(p.x * 2.3 + TIME * 0.7) * 0.048;
		float wash = distance_from_shore + curve + sin(TIME * 1.12 + p.x * 0.57) * 0.049;
		float foam = 1.0 - smoothstep(0.018, 0.082, abs(wash));
		float lace = smoothstep(0.25, 0.90, sin(p.x * 18.0 + swell * 1.95));
		vec3 wet_sand = sand.rgb * mix(0.83, 1.0, smoothstep(0.03, 0.18, -distance_from_shore));
		water = mix(wet_sand, water, smoothstep(-0.03, 0.07, wash));
		float breaking = 1.0 - smoothstep(0.01, 0.055, abs(wash - 0.25 + drift * 0.041));
		water = mix(water, foam_tone.rgb, breaking * lace * 0.31);
		water = mix(water, foam_tone.rgb, foam * (0.66 + 0.27 * lace));
	}
	ALBEDO = water;
	ROUGHNESS = 0.98;
}
