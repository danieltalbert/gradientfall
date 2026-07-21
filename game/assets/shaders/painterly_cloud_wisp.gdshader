shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back;

// Translucent wind-sheared satellite forms. They share the core palette but
// dissolve through view-angle softness and broad three-dimensional breakup.
uniform vec4 top_tint : source_color = vec4(0.98, 0.99, 1.0, 1.0);
uniform vec4 middle_tint : source_color = vec4(0.82, 0.88, 0.95, 1.0);
uniform vec4 underside_tint : source_color = vec4(0.43, 0.53, 0.67, 1.0);
uniform vec4 rim_tint : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec3 sun_direction = vec3(0.35, 0.72, 0.28);
uniform float sun_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_position;
varying vec3 world_normal;
varying float cloud_height;
varying float lobe_tone;
varying float breakup_phase;
varying float density;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(cell);
	float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));
	float near_z = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
	float far_z = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
	return mix(near_z, far_z, f.z);
}

void vertex() {
	vec3 local_sample = VERTEX * 0.034 + vec3(COLOR.b * 9.0, TIME * 0.006, 0.0);
	float erosion_shape = value_noise(local_sample) * 0.64
			+ value_noise(local_sample * 2.47 + vec3(2.0, 7.0, 5.0)) * 0.36;
	float flutter = sin(TIME * 0.085 + COLOR.b * 6.28318 + VERTEX.x * 0.012) * 0.18;
	VERTEX += NORMAL * ((erosion_shape - 0.5) * 1.40 + flutter);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	cloud_height = COLOR.r;
	lobe_tone = COLOR.g;
	breakup_phase = COLOR.b;
	density = COLOR.a;
}

void fragment() {
	vec3 normal = normalize(world_normal);
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	vec3 light_direction = normalize(sun_direction);
	float lower_to_middle = smoothstep(0.015, 0.64, cloud_height);
	float middle_to_top = smoothstep(0.44, 0.99, cloud_height);
	vec3 base = mix(underside_tint.rgb, middle_tint.rgb, lower_to_middle);
	base = mix(base, top_tint.rgb, middle_to_top);
	float sun_facing = smoothstep(-0.58, 0.78, dot(normal, light_direction));
	base *= mix(0.84, 1.055, sun_facing * sun_strength);
	base *= 0.96 + (lobe_tone - 0.5) * 0.055;

	float ndv = clamp(dot(normal, view_direction), 0.0, 1.0);
	float soft_contour = smoothstep(-0.01, 0.38, ndv);
	vec3 moving_sample = world_position * 0.020 + vec3(TIME * 0.004, breakup_phase * 4.7, 0.0);
	float broad_noise = value_noise(moving_sample);
	float fine_noise = value_noise(moving_sample * 2.7 + vec3(5.0, 11.0, 3.0));
	float breakup = smoothstep(0.32, 0.72, broad_noise * 0.70 + fine_noise * 0.30 + density * 0.20);
	float alpha = density * 0.46 * soft_contour * breakup;

	float fresnel = pow(1.0 - ndv, 2.8);
	float sunward_edge = smoothstep(-0.10, 0.76, dot(normal, light_direction));
	base = mix(base, rim_tint.rgb, fresnel * sunward_edge * sun_strength * 0.24);
	ALBEDO = max(base, vec3(0.0));
	ALPHA = clamp(alpha, 0.0, 0.58);
}
