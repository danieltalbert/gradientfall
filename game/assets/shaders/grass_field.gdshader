shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, specular_disabled;
// The infinite fine-grass carpet (Ghost of Tsushima technique, Danny's
// fidelity decree): ~400k thin blades live in one camera-centered tile.
// Each blade's instance origin is wrapped toroidally around the camera in
// the vertex shader, so the field is ALWAYS dense wherever you stand and no
// CPU ever touches a blade again after boot. Blades read the terrain
// heightmap texture to find the ground, die on water/steep slopes, sway to
// a gust wave that visibly ROLLS across the meadow, and fade into the
// terrain's matching green before the tile edge can ever be seen.

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float terrain_size = 480.0;
uniform float water_level = 0.0;
uniform float tile = 130.0;
uniform float fade_start = 46.0;
uniform float fade_end = 62.0;
uniform vec4 color_a : source_color = vec4(0.31, 0.55, 0.15, 1.0);
uniform vec4 color_b : source_color = vec4(0.44, 0.64, 0.18, 1.0);
uniform vec4 color_gold : source_color = vec4(0.7, 0.6, 0.24, 1.0);
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.35;

varying float v_tip;
varying vec3 v_col;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_tip = UV.y;
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec2 cam = CAMERA_POSITION_WORLD.xz;

	// Toroidal wrap of the instance origin around the camera.
	vec2 rel = inst.xz - cam;
	vec2 wrapped = mod(rel + tile * 0.5, tile) - tile * 0.5;
	vec2 nxz = cam + wrapped;

	float rnd = hash21(inst.xz * 7.31);

	// Local blade shape: rotate a random yaw, apply size variance.
	vec2 lo = VERTEX.xz - inst.xz;
	float ang = rnd * 6.2831;
	vec2 rlo = vec2(lo.x * cos(ang) - lo.y * sin(ang), lo.x * sin(ang) + lo.y * cos(ang));
	float hscale = 0.7 + 0.6 * hash21(inst.xz * 3.17);

	// Ground lookup.
	vec2 uv = (nxz + terrain_size * 0.5) / terrain_size;
	vec2 hg = textureLod(height_map, uv, 0.0).rg;
	float margin = terrain_size * 0.5 - 14.0;
	float alive = step(water_level + 0.35, hg.r) * step(0.78, hg.g)
			* step(abs(nxz.x), margin) * step(abs(nxz.y), margin);
	float fade = (1.0 - smoothstep(fade_start, fade_end, length(wrapped))) * alive;

	// Gust wave rolling across the field + per-blade flutter.
	float phase = dot(nxz, normalize(wind_dir)) * 0.12 - TIME * wind_speed;
	float gust = sin(phase) * 0.5 + 0.5;
	gust = gust * gust;
	float sway = (gust * 0.4 + 0.05 * sin(TIME * 3.7 + rnd * 6.2831)) * v_tip * v_tip;

	VERTEX.xz = nxz + rlo + normalize(wind_dir) * sway;
	VERTEX.y = hg.r + (VERTEX.y - inst.y) * hscale * fade;

	// Color: patchy hue drifts + gold swathes + gust shimmer + root shadow.
	float patch = vnoise(nxz * 0.05);
	vec3 c = mix(color_a.rgb, color_b.rgb, hash21(inst.xz * 3.7));
	c = mix(c, color_gold.rgb, smoothstep(0.62, 0.85, patch) * 0.6);
	c *= 1.0 + 0.14 * gust * v_tip;
	v_col = pow(c, vec3(2.2));
}

void fragment() {
	// Dark at the root (fake ambient occlusion in the sward), lit at the tip.
	ALBEDO = v_col * mix(0.42, 1.08, v_tip);
	BACKLIGHT = v_col * 0.4;  // sun through blades — the translucency of real grass
	ROUGHNESS = 0.9;
}
