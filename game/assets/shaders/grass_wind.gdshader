shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
// Taller meadow accents. The shared mesh is built from five curved ribbons;
// this material adds two-scale travelling wind, individual blade flutter,
// root occlusion, and gentle back-lighting without turning the field neon.

uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float sway_strength : hint_range(0.0, 0.7) = 0.21;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.05;

varying float v_tip;
varying float v_gust;
varying float v_visibility;
varying vec3 v_col;

void vertex() {
	v_tip = UV.y;
	// MultiMesh colors are authored as display values rather than source_color
	// uniforms, so they need explicit conversion to the renderer's linear space.
	v_col = pow(COLOR.rgb, vec3(2.2));
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_direction = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	vec2 local_direction = normalize(vec2(
		dot(world_direction, model_x), dot(world_direction, model_z)
	));
	vec2 local_cross = vec2(-local_direction.y, local_direction.x);

	float march = dot(world_position.xz, normalize(wind_dir)) * 0.055 - TIME * sway_speed;
	float crossing = dot(world_position.xz, vec2(-wind_dir.y, wind_dir.x)) * 0.024 + TIME * 0.29;
	float wave = sin(march) * 0.7 + sin(crossing) * 0.3;
	v_gust = smoothstep(-0.58, 0.76, wave);
	v_gust *= v_gust;
	float tip_weight = pow(v_tip, 1.55);
	float flutter = sin(TIME * 3.6 + UV2.x * 6.2831853 + world_position.x * 0.17 + world_position.z * 0.11);
	VERTEX.xz += local_direction * ((0.025 + v_gust * sway_strength) * tip_weight);
	VERTEX.xz += local_cross * (flutter * 0.018 * tip_weight);
	VERTEX.y -= v_gust * 0.035 * tip_weight;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.4));

	float camera_distance = distance(world_position, CAMERA_POSITION_WORLD);
	v_visibility = 1.0 - smoothstep(148.0, 218.0, camera_distance);
	VERTEX *= v_visibility;
}

void fragment() {
	if (v_visibility < 0.015) {
		discard;
	}
	ALBEDO = v_col * mix(0.82, 1.06, smoothstep(0.0, 0.88, v_tip));
	ALBEDO *= 1.0 + v_gust * v_tip * 0.025;
	EMISSION = v_col * mix(0.09, 0.05, v_tip);
	BACKLIGHT = v_col * (0.26 + v_tip * 0.18);
	ROUGHNESS = 0.95;
	SPECULAR = 0.075;
	RIM = 0.07 * smoothstep(0.28, 1.0, v_tip);
	RIM_TINT = 0.28;
}
