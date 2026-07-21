shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, specular_schlick_ggx;
// Camera-wrapped meadow carpet. Every MultiMesh transform carries a loose
// three-ribbon tuft; this shader wraps the tuft around the active camera,
// plants it on the height map, and drives broad coherent wind fronts. The
// geometry shrinks in every axis at the tile edge, so grass dissolves into
// the terrain instead of leaving flat splats or a visible coverage ring.

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float terrain_size = 480.0;
uniform float water_level = 0.0;
uniform float tile = 196.0;
uniform float fade_start = 80.0;
uniform float fade_end = 96.0;
uniform vec4 color_a : source_color = vec4(0.34, 0.53, 0.14, 1.0);
uniform vec4 color_b : source_color = vec4(0.48, 0.66, 0.2, 1.0);
uniform vec4 color_gold : source_color = vec4(0.68, 0.56, 0.2, 1.0);
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.05;
uniform float wind_strength : hint_range(0.0, 0.7) = 0.19;

varying float v_tip;
varying float v_gust;
varying float v_visibility;
varying vec3 v_col;

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

vec2 rotate_2d(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	v_tip = UV.y;
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - instance_origin;
	vec2 camera_xz = CAMERA_POSITION_WORLD.xz;

	// Toroidal wrapping creates continuous coverage with no CPU updates.
	vec2 relative = instance_origin.xz - camera_xz;
	vec2 wrapped = mod(relative + tile * 0.5, tile) - tile * 0.5;
	vec2 planted_xz = camera_xz + wrapped;
	float random = hash21(instance_origin.xz * 7.31);
	float angle = random * 6.2831853;
	local.xz = rotate_2d(local.xz, angle);
	NORMAL.xz = rotate_2d(NORMAL.xz, angle);
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.4));

	// Height-map R stores height and G stores terrain normal Y.
	vec2 terrain_uv = (planted_xz + terrain_size * 0.5) / terrain_size;
	vec2 height_ground = textureLod(height_map, terrain_uv, 0.0).rg;
	float margin = terrain_size * 0.5 - 14.0;
	float alive = step(water_level + 0.35, height_ground.r)
			* step(0.74, height_ground.g)
			* step(abs(planted_xz.x), margin)
			* step(abs(planted_xz.y), margin);
	float radial_fade = 1.0 - smoothstep(fade_start, fade_end, length(wrapped));
	v_visibility = alive * radial_fade;

	float height_scale = 0.82 + 0.3 * hash21(instance_origin.xz * 3.17);
	local.y *= height_scale;
	// Scaling width as well as height makes rejected and distant tufts truly
	// zero-area; this is the detail that removes the old needle/splat look.
	local *= v_visibility;

	vec2 direction = normalize(wind_dir);
	vec2 cross_direction = vec2(-direction.y, direction.x);
	float march = dot(planted_xz, direction) * 0.055 - TIME * wind_speed;
	float cross_wave = dot(planted_xz, cross_direction) * 0.027 + TIME * 0.32;
	float broad_wave = sin(march) * 0.72 + sin(cross_wave) * 0.28;
	v_gust = smoothstep(-0.55, 0.78, broad_wave);
	v_gust *= v_gust;
	float blade_phase = UV2.x * 6.2831853 + random * 4.0;
	float flutter = sin(TIME * 3.4 + blade_phase + dot(planted_xz, cross_direction) * 0.22);
	float tip_weight = pow(v_tip, 1.55);
	vec2 bend = direction * ((0.018 + v_gust * wind_strength) * tip_weight);
	bend += cross_direction * (flutter * 0.014 * tip_weight);

	VERTEX = vec3(planted_xz.x, height_ground.r, planted_xz.y) + local;
	VERTEX.xz += bend * v_visibility;

	// Broad spatial color drifts bind thousands of tufts into natural swaths.
	float patch = vnoise(planted_xz * 0.018);
	float dry = vnoise(planted_xz * 0.009 + vec2(18.0, -31.0));
	vec3 green = mix(color_a.rgb, color_b.rgb, patch * 0.82 + random * 0.18);
	float gold_amount = smoothstep(0.62, 0.86, dry) * 0.38;
	v_col = mix(green, color_gold.rgb, gold_amount);
}

void fragment() {
	if (v_visibility < 0.015) {
		discard;
	}
	// Root occlusion is a gentle value roll, never a separate black stripe.
	// A small albedo-colored ambient lift keeps back-facing ribbons green.
	ALBEDO = v_col * mix(0.82, 1.06, smoothstep(0.0, 0.88, v_tip));
	ALBEDO *= 1.0 + v_gust * v_tip * 0.025;
	EMISSION = v_col * mix(0.095, 0.055, v_tip);
	BACKLIGHT = v_col * (0.28 + 0.18 * v_tip);
	ROUGHNESS = 0.94;
	SPECULAR = 0.08;
	RIM = 0.075 * smoothstep(0.25, 1.0, v_tip);
	RIM_TINT = 0.3;
}
