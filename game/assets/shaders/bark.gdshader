shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Analytic bark shared by trunk, root flare, boughs, and twigs. Several noise
// scales break the vertical ridges into plates, hairline cracks, and quiet moss
// staining. Tall, radial branch vertices follow the same wind front as leaves
// while the roots stay planted.

uniform vec4 bark_color : source_color = vec4(0.42, 0.3, 0.19, 1.0);
uniform vec4 bark_light : source_color = vec4(0.57, 0.42, 0.25, 1.0);
uniform vec4 groove_color : source_color = vec4(0.24, 0.15, 0.085, 1.0);
uniform vec4 moss_color : source_color = vec4(0.2, 0.31, 0.11, 1.0);
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.05;
uniform float tree_height = 9.0;

varying vec2 v_uv;
varying vec3 v_world_position;
varying vec3 v_local_position;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_uv = UV;
	vec3 initial_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_direction = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	vec2 local_direction = normalize(vec2(
		dot(world_direction, model_x), dot(world_direction, model_z)
	));
	float march = dot(initial_world.xz, normalize(wind_dir)) * 0.045 - TIME * wind_speed;
	float gust = smoothstep(-0.62, 0.8, sin(march));
	gust *= gust;
	float height_weight = smoothstep(0.28, 0.92, clamp(VERTEX.y / tree_height, 0.0, 1.0));
	float branch_weight = smoothstep(0.32, 1.5, length(VERTEX.xz));
	VERTEX.xz += local_direction * gust * 0.07 * height_weight * branch_weight;
	v_local_position = VERTEX;
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float circumference = v_uv.x * 6.2831853;
	float wander = vnoise(vec2(v_uv.x * 7.0, v_world_position.y * 0.42)) * 3.2;
	float broad_ridge = sin(circumference * 8.0 + wander) * 0.5 + 0.5;
	broad_ridge = smoothstep(0.18, 0.82, broad_ridge);
	float fine_ridge = sin(circumference * 21.0 + v_world_position.y * 0.24 + wander) * 0.5 + 0.5;
	float plates = vnoise(vec2(v_uv.x * 23.0, v_world_position.y * 2.6));
	float horizontal_crack = smoothstep(0.87, 0.965, plates);
	float vertical_crack = smoothstep(0.91, 0.985, vnoise(vec2(v_uv.x * 58.0, v_world_position.y * 0.72)));

	vec3 color = mix(groove_color.rgb, bark_color.rgb, broad_ridge);
	color = mix(color, bark_light.rgb, fine_ridge * 0.22);
	color = mix(color, groove_color.rgb, horizontal_crack * 0.72 + vertical_crack * 0.4);
	float tonal_drift = vnoise(v_world_position.xz * 0.43 + v_world_position.y * 0.08);
	color *= 0.86 + tonal_drift * 0.24;
	float low_trunk = 1.0 - smoothstep(1.2, 4.8, max(v_local_position.y, 0.0));
	float moss = smoothstep(0.58, 0.84, vnoise(v_world_position.xz * 0.68 + vec2(9.0, -13.0)));
	color = mix(color, moss_color.rgb, moss * low_trunk * 0.24);
	ALBEDO = color;
	EMISSION = color * 0.035;
	ROUGHNESS = mix(0.82, 1.0, horizontal_crack);
	SPECULAR = 0.1;
	RIM = 0.08;
	RIM_TINT = 0.28;
}
