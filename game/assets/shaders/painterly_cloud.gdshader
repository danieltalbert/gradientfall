shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back;

// Opaque heart of each cloud bank. Vertex color is non-color payload authored
// by CloudLayer: R = whole-cloud height, G = per-lobe tone, B = motion phase.
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
varying float shape_phase;

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
	// Low-frequency normal displacement breaks the implicit mesh's cell edges
	// into a slowly evolving vapour contour. It stays deliberately sub-meter so
	// the authored broad bank remains readable from the meadow.
	vec3 local_sample = VERTEX * 0.026 + vec3(COLOR.b * 7.0, TIME * 0.003, 0.0);
	float billow = value_noise(local_sample) * 0.68
			+ value_noise(local_sample * 2.31 + vec3(4.0, 9.0, 2.0)) * 0.32;
	float breathe = sin(TIME * 0.055 + COLOR.b * 6.28318 + VERTEX.x * 0.009) * 0.10;
	VERTEX += NORMAL * ((billow - 0.5) * 1.15 + breathe);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	cloud_height = COLOR.r;
	lobe_tone = COLOR.g;
	shape_phase = COLOR.b;
}

void fragment() {
	vec3 normal = normalize(world_normal);
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	vec3 light_direction = normalize(sun_direction);

	// Broad overlapping ramps replace the old obvious dark-base/white-top cut.
	// Cloud height gives self-shadowing while normal direction supplies rounded
	// sunlit depth across the fused surface.
	float lower_to_middle = smoothstep(0.015, 0.62, cloud_height);
	float middle_to_top = smoothstep(0.42, 0.98, cloud_height);
	vec3 base = mix(underside_tint.rgb, middle_tint.rgb, lower_to_middle);
	base = mix(base, top_tint.rgb, middle_to_top);
	float sun_facing = smoothstep(-0.58, 0.78, dot(normal, light_direction));
	float sky_facing = smoothstep(-0.48, 0.88, normal.y);
	float wrapped_light = mix(0.79, 1.075, sun_facing * sun_strength);
	wrapped_light *= mix(0.84, 1.035, sky_facing);

	// Low-frequency mottling and per-lobe value shifts create painterly depth
	// without covering the cloud in noisy procedural grain.
	float broad_noise = value_noise(world_position * 0.009 + vec3(shape_phase * 5.0, 0.0, 0.0));
	float fine_noise = value_noise(world_position * 0.026 + vec3(7.0, 3.0, 11.0));
	float painted_value = (broad_noise - 0.5) * 0.105 + (fine_noise - 0.5) * 0.035;
	painted_value += (lobe_tone - 0.5) * 0.055;
	base *= wrapped_light + painted_value;
	// Sunward upper volumes borrow a little warm top colour; lower volumes keep
	// their blue-grey aerial depth even under a strong noon light.
	float illuminated_volume = sun_facing * smoothstep(0.22, 0.92, cloud_height) * sun_strength;
	base = mix(base, top_tint.rgb, illuminated_volume * 0.16);
	base *= mix(0.82, 1.025, smoothstep(0.02, 0.72, cloud_height));

	// A sun-biased Fresnel band reads as silver lining/backlight. Restricting it
	// to upward and sunward facets avoids a generic white outline around blobs.
	float ndv = clamp(dot(normal, view_direction), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 2.9);
	float sunward_edge = smoothstep(-0.10, 0.78, dot(normal, light_direction));
	float rim = fresnel * sunward_edge * mix(0.10, 0.60, sun_strength);
	rim *= mix(0.44, 1.0, sky_facing);
	base = mix(base, rim_tint.rgb, clamp(rim, 0.0, 0.28));

	ALBEDO = max(base, vec3(0.0));
	// View-normal fade gives the fused cloud a soft photographic contour. Broad
	// noise only erodes that contour; the dense interior remains fully opaque
	// and stable for TAA/depth prepass.
	float contour_noise = value_noise(world_position * 0.021 + vec3(TIME * 0.0025, shape_phase * 8.0, 13.0));
	float contour = smoothstep(-0.005, 0.075, ndv + (contour_noise - 0.5) * 0.035);
	ALPHA = clamp(contour * 1.28, 0.0, 1.0);
}
