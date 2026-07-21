shader_type spatial;
render_mode specular_toon;
// Stylized water (GDD §10: water with depth color, foam edges, sparkle).
// Analytic sine-sum ripples perturb the normal (no textures), the depth
// buffer drives shallow→deep color and a white foam ring where the water
// meets the shore, and low roughness gives a toon sun-glint.

uniform vec4 deep_color : source_color = vec4(0.07, 0.28, 0.42, 0.9);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.6, 0.62, 0.55);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 0.9);
uniform float foam_depth : hint_range(0.05, 2.0) = 0.55;
uniform float depth_fade : hint_range(0.5, 8.0) = 2.8;
uniform float ripple_scale : hint_range(0.05, 2.0) = 0.55;
uniform float ripple_speed : hint_range(0.0, 3.0) = 0.9;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D depth_tex : hint_depth_texture;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

	float shore = 1.0 - smoothstep(0.0, foam_depth, thickness);
	float deep_mix = smoothstep(0.0, depth_fade, thickness);
	vec4 body = mix(shallow_color, deep_color, deep_mix);

	// Gentle moving foam flecks near the shoreline.
	float foam_band = smoothstep(0.3, 1.0, shore + 0.35 * sin(p.x * 6.0 + p.y * 5.0 + t * 2.0));

	ALBEDO = mix(body.rgb, foam_color.rgb, foam_band);
	ALPHA = mix(body.a, foam_color.a, foam_band);
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.1;
}
