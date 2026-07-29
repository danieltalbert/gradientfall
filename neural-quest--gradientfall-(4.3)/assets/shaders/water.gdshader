shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;
// Stylized water (GDD §10: water with depth color, foam edges, sparkle).
// Analytic sine-sum ripples perturb the normal (no textures), the depth
// buffer drives shallow→deep color and a white foam ring where the water
// meets the shore, and low roughness gives a toon sun-glint.

uniform vec4 deep_color : source_color = vec4(0.018, 0.17, 0.25, 0.96);
uniform vec4 shallow_color : source_color = vec4(0.09, 0.43, 0.46, 0.82);
uniform vec4 foam_color : source_color = vec4(0.82, 0.96, 0.91, 0.96);
uniform vec4 sky_reflection : source_color = vec4(0.36, 0.62, 0.78, 1.0);
uniform float foam_depth : hint_range(0.05, 2.0) = 0.72;
uniform float depth_fade : hint_range(0.5, 8.0) = 3.6;
uniform float ripple_scale : hint_range(0.05, 2.0) = 0.55;
uniform float ripple_speed : hint_range(0.0, 3.0) = 0.9;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wave_height : hint_range(0.0, 0.25) = 0.075;
uniform vec2 pond_center = vec2(95.0, 10.0);
uniform float pond_radius = 24.0;
uniform sampler2D depth_tex : hint_depth_texture;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 v_wpos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float broad = sin(wp.x * 0.18 + TIME * 0.65) * 0.55
			+ sin(wp.z * 0.24 - TIME * 0.48) * 0.30
			+ sin((wp.x + wp.z) * 0.11 + TIME * 0.32) * 0.15;
	VERTEX.y += broad * wave_height;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float wave_h(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.3) * 0.5
			+ sin(p.y * 2.3 - t * 1.1) * 0.3
			+ sin((p.x + p.y) * 1.1 + t * 1.7) * 0.2;
}

void fragment() {
	// Ripple normal from analytic height slopes.
	vec2 p = v_wpos.xz * ripple_scale;
	float t = TIME * ripple_speed;
	float e = 0.12;
	float dhx = wave_h(p + vec2(e, 0.0), t) - wave_h(p - vec2(e, 0.0), t);
	float dhz = wave_h(p + vec2(0.0, e), t) - wave_h(p - vec2(0.0, e), t);
	vec3 n_world = normalize(vec3(-dhx * ripple_strength, 1.0, -dhz * ripple_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Water thickness from the depth buffer (official reconstruction).
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float thickness = -view_pos.z - (-VERTEX.z);

	float depth_shore = 1.0 - smoothstep(0.0, foam_depth, thickness);
	// The procedural pond has a known soft circular bank. Folding that shape
	// into the foam mask keeps a readable moving shore even where the low-poly
	// terrain and depth buffer meet at a shallow viewing angle.
	float radial_distance = distance(v_wpos.xz, pond_center);
	float radial_shore = 1.0 - smoothstep(0.0, 1.65, abs(radial_distance - pond_radius));
	float shore = max(depth_shore, radial_shore);
	float deep_mix = smoothstep(0.0, depth_fade, thickness);
	vec4 body = mix(shallow_color, deep_color, deep_mix);

	// Gentle moving foam flecks near the shoreline.
	float foam_noise = value_noise(p * 5.0 + vec2(t * 0.6, -t * 0.35));
	float foam_ripple = sin(p.x * 7.0 + p.y * 5.0 + t * 2.4) * 0.13;
	float foam_band = smoothstep(0.58, 0.86, shore + foam_noise * 0.34 + foam_ripple);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec2 refract_uv = SCREEN_UV + n_world.xz * 0.006 * (1.0 - deep_mix);
	vec3 refracted = textureLod(screen_tex, refract_uv, 1.0).rgb;
	vec3 water_color = mix(refracted * body.rgb, body.rgb, 0.66 + deep_mix * 0.24);
	water_color = mix(water_color, sky_reflection.rgb, fresnel * 0.66);
	float glint_lines = max(0.0,
			sin(p.x * 8.3 + t * 2.2) * sin(p.y * 6.7 - t * 1.5));
	float glint = pow(glint_lines, 18.0) * smoothstep(0.12, 0.78, fresnel);

	ALBEDO = mix(water_color, foam_color.rgb, foam_band);
	ALPHA = mix(body.a, foam_color.a, foam_band);
	ROUGHNESS = mix(0.12, 0.035, fresnel);
	SPECULAR = 0.82;
	METALLIC = 0.0;
	EMISSION = foam_color.rgb * (foam_band * 0.09 + glint * 0.34);
}
