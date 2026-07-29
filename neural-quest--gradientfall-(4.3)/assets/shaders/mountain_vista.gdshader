shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_back;

// Distant mountain material. Geometry supplies a ridge/gully mask in UV.x
// and normalized altitude in UV.y; this shader turns those authored forms
// into broken strata, accumulated snow, cool ravines, and rank-specific
// aerial perspective without relying on image textures.

group_uniforms rock;
uniform float rock_detail : hint_range(0.0, 0.5) = 0.22;
uniform float detail_scale : hint_range(0.001, 0.2) = 0.035;
uniform float gully_strength : hint_range(0.0, 0.65) = 0.28;
uniform float strata_strength : hint_range(0.0, 0.5) = 0.18;
uniform float fracture_strength : hint_range(0.0, 0.5) = 0.19;
uniform float scree_strength : hint_range(0.0, 0.5) = 0.2;
uniform float seed_offset = 0.0;

group_uniforms snow;
uniform vec4 snow_tint : source_color = vec4(0.84, 0.91, 0.96, 1.0);
uniform float snowline : hint_range(0.0, 1.0) = 0.68;
uniform float snow_softness : hint_range(0.01, 0.25) = 0.075;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.8;

group_uniforms atmosphere;
uniform vec4 haze_tint : source_color = vec4(0.48, 0.62, 0.74, 1.0);
uniform float haze_amount : hint_range(0.0, 0.8) = 0.12;
uniform vec4 shadow_fill : source_color = vec4(0.32, 0.44, 0.58, 1.0);
uniform float fill_amount : hint_range(0.0, 0.25) = 0.055;

varying vec3 v_world_position;
varying vec3 v_world_normal;
varying vec3 v_authored_color;
varying float v_ridge;
varying float v_altitude;


float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0));
	float low = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
	float high = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
	return mix(low, high, f.z);
}


float fbm(vec3 p) {
	float result = 0.0;
	float weight = 0.56;
	for (int octave = 0; octave < 4; octave++) {
		result += value_noise(p) * weight;
		p = p * 2.07 + vec3(7.1, 3.7, 11.9);
		weight *= 0.5;
	}
	return result / 1.05;
}


void vertex() {
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	// Procedural meshes author display-space colors, matching the terrain.
	v_authored_color = pow(COLOR.rgb, vec3(2.2));
	v_ridge = UV.x;
	v_altitude = UV.y;
}


void fragment() {
	vec3 seed = vec3(seed_offset, seed_offset * 0.37, -seed_offset * 0.61);
	float broad = fbm(v_world_position * detail_scale * 0.24 + seed);
	float fine = fbm(v_world_position * detail_scale + seed * 1.9);
	vec3 world_normal = normalize(v_world_normal);
	float face_slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float cliff_face = smoothstep(0.26, 0.82, face_slope);

	// The geometry-authored ridge channel keeps spurs readable even after fog;
	// broad and fine noise break the color into natural rock plates.
	float ridge_light = smoothstep(0.12, 0.9, v_ridge);
	float ravine = mix(1.0 - gully_strength, 1.075, ridge_light);
	vec3 rock_color = v_authored_color * ravine;
	rock_color *= 1.0 + (broad - 0.5) * rock_detail;
	rock_color *= 1.0 + (fine - 0.5) * rock_detail * 0.42;

	// Broken, slightly tilted sediment bands. They darken only fragments of a
	// contour, avoiding the striped-cake look of perfectly continuous lines.
	float phase = v_world_position.y * 0.112
			+ (broad - 0.5) * 7.5
			+ v_world_position.x * 0.006
			+ seed_offset;
	float contour = pow(0.5 + 0.5 * sin(phase), 10.0);
	float broken = smoothstep(0.34, 0.69,
			value_noise(v_world_position * 0.024 + seed * 2.4));
	float strata = contour * broken * strata_strength
			* smoothstep(0.08, 0.32, v_altitude)
			* (1.0 - smoothstep(0.78, 0.98, v_altitude));
	rock_color *= 1.0 - strata;

	// Cross-cut fractures and ledge lips break the long smooth faces left by
	// terrain interpolation. Noise interrupts both so no line circles a peak.
	float fracture_x = pow(abs(sin(
			v_world_position.x * 0.047 + broad * 5.2 + seed_offset
	)), 18.0);
	float fracture_z = pow(abs(sin(
			v_world_position.z * 0.039 - fine * 4.1 - seed_offset * 0.7
	)), 20.0);
	float fracture_gate = smoothstep(0.46, 0.7,
			value_noise(v_world_position * 0.031 + seed * 3.1));
	float fracture = max(fracture_x, fracture_z) * fracture_gate * cliff_face;
	fracture *= smoothstep(0.12, 0.38, v_altitude)
			* (1.0 - smoothstep(0.86, 1.0, v_altitude));
	rock_color *= 1.0 - fracture * fracture_strength;

	float ledge_phase = v_world_position.y * 0.165 + broad * 5.7 + seed_offset * 0.4;
	float ledge_lip = pow(0.5 + 0.5 * sin(ledge_phase), 16.0);
	ledge_lip *= smoothstep(0.38, 0.74, fine) * cliff_face;
	ledge_lip *= smoothstep(0.14, 0.3, v_altitude)
			* (1.0 - smoothstep(0.76, 0.94, v_altitude));
	rock_color = mix(rock_color, rock_color * 1.14, ledge_lip * 0.55);
	rock_color *= 1.0 - ledge_lip * strata_strength * 0.34;

	// Loose lower-slope material forms patchy fans below gullies rather than a
	// single smooth color ramp. Fine noise reads as gravel only at close range.
	float lower_face = 1.0 - smoothstep(0.2, 0.58, v_altitude);
	float gully = 1.0 - smoothstep(0.2, 0.72, v_ridge);
	float scree_gate = smoothstep(0.42, 0.7,
			fine * 0.68 + value_noise(v_world_position * 0.13 + seed) * 0.32);
	float scree = lower_face * cliff_face * scree_gate * (0.42 + gully * 0.58);
	vec3 scree_color = rock_color * mix(0.76, 1.14,
			value_noise(v_world_position * 0.22 + seed * 1.3));
	rock_color = mix(rock_color, scree_color, scree * scree_strength);

	// Snow wanders around each peak, favors upward shelves, and breaks over
	// exposed ridge ribs. Per-instance snowline/amount keeps the range varied.
	float snow_warp = (broad - 0.5) * 0.17 + (fine - 0.5) * 0.045;
	float height_snow = smoothstep(
			snowline - snow_softness,
			snowline + snow_softness,
			v_altitude + snow_warp
	);
	float shelf = mix(0.34, 1.0, smoothstep(0.05, 0.72, world_normal.y));
	float wind_scour = mix(1.0, 0.56, smoothstep(0.5, 0.94, v_ridge));
	float summit_snow = height_snow * shelf * wind_scour;
	float gully_descent = smoothstep(
			snowline - 0.24, snowline - 0.055, v_altitude + snow_warp
	);
	float gully_break = smoothstep(0.3, 0.58,
			value_noise(v_world_position * 0.028 + seed * 4.2));
	float gully_snow = gully_descent * gully * mix(0.46, 0.82, shelf) * gully_break;
	float snow_mask = max(summit_snow, gully_snow * 0.82) * snow_amount;
	snow_mask *= 1.0 - fracture * 0.42;
	vec3 snow_color = snow_tint.rgb * mix(0.82, 1.06, broad);
	vec3 color = mix(rock_color, snow_color, clamp(snow_mask, 0.0, 0.94));

	// Each geometric rank carries a little more blue atmosphere. Godot's fog
	// then finishes the depth cue instead of flattening every rank equally.
	color = mix(color, haze_tint.rgb, haze_amount);
	ALBEDO = color;
	ROUGHNESS = mix(0.98, 0.82, snow_mask);
	SPECULAR = mix(0.08, 0.2, snow_mask);
	EMISSION = color * fill_amount * shadow_fill.rgb;
	float fresnel = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += haze_tint.rgb * pow(fresnel, 4.0) * 0.018;
}
