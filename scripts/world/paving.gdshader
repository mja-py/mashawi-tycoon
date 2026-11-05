shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 stone : source_color = vec4(0.68, 0.54, 0.42, 1.0);
uniform vec4 walk : source_color = vec4(0.61, 0.47, 0.35, 1.0);
uniform vec4 inlay : source_color = vec4(0.42, 0.29, 0.22, 1.0);
uniform vec2 slab = vec2(0.66, 0.41);
uniform float walk_center = 0.25;
uniform float walk_half_width = 0.42;
uniform bool mosaic = false;

varying vec2 ground;

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = ground;
	// Filter joints in world units. At a grazing angle the grout fades smoothly
	// into the stone instead of flickering between individual screen pixels.
	float pixel = max(max(fwidth(p.x), fwidth(p.y)), 0.002);
	float row = floor(p.y / slab.y);
	vec2 grid = vec2(p.x / slab.x + 0.5 * mod(row, 2.0), p.y / slab.y);
	vec2 tile = fract(grid);
	vec2 edge = min(tile, 1.0 - tile) * slab;
	float joint = 1.0 - smoothstep(0.003, 0.009 + pixel, min(edge.x, edge.y));
	joint *= 1.0 - smoothstep(0.018, 0.065, pixel);

	float mix_stone = fract(sin(dot(floor(grid), vec2(41.37, 25.59))) * 421.3);
	float grain = sin(p.x * 21.0 + p.y * 11.0) * sin(p.y * 25.0 - p.x * 4.0);
	float lane_distance = abs(p.y - walk_center) - walk_half_width;
	float lane = 1.0 - smoothstep(-pixel, pixel, lane_distance);
	float border = 1.0 - smoothstep(0.021 - pixel, 0.032 + pixel, abs(lane_distance));
	vec3 color = mix(stone.rgb, walk.rgb, lane);
	color *= 0.94 + mix_stone * 0.10 + grain * 0.015;
	color = mix(color, color * 0.70, joint * 0.53);
	color = mix(color, inlay.rgb, border * 0.82);
	if (mosaic) {
		float repeat_x = abs(fract(p.x / 0.30 + 0.5) - 0.5) * 0.30;
		float fret = 1.0 - smoothstep(0.044 - pixel, 0.044 + pixel, repeat_x + abs(lane_distance + 0.058));
		color = mix(color, inlay.rgb, fret * 0.62);
	}
	ALBEDO = color;
}
