shader_type spatial;
render_mode specular_schlick_ggx;
// Metal for the blade, guard, pommel, buckle, clasp. Stylized-real metal is
// mostly its highlight: a hard cel-stepped hot band that sweeps as the sword
// moves, brushed anisotropic streaks along the polish direction (UV.y runs
// along the blade), a cool sky tint in the fresnel, and per-vertex COLOR
// carrying nicks/patina painted at build time. Blades additionally get a
// bright honed line at the edge bevel via COLOR.a = edge mask.

group_uniforms surface;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;
uniform vec4 edge_color : source_color = vec4(0.95, 0.97, 1.0, 1.0);

group_uniforms brushed;
uniform float streak_scale : hint_range(20.0, 800.0) = 260.0;
uniform float streak_amount : hint_range(0.0, 0.4) = 0.10;

group_uniforms cel;
uniform float band_lit_edge : hint_range(-0.5, 0.9) = 0.16;
uniform float band_soft : hint_range(0.005, 0.3) = 0.04;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.30;

group_uniforms speculars;
uniform float spec_power : hint_range(8.0, 400.0) = 130.0;
uniform float spec_strength : hint_range(0.0, 4.0) = 1.9;

group_uniforms skyreflect;
uniform vec4 sky_tint : source_color = vec4(0.58, 0.72, 0.92, 1.0);
uniform float sky_amount : hint_range(0.0, 1.0) = 0.30;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.08;

varying vec3 v_col;
varying vec2 v_uv;
varying float v_edge;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	v_uv = UV;
	v_edge = COLOR.a;
}

void fragment() {
	vec3 albedo = v_col * albedo_tint.rgb * albedo_boost;
	// Brushed streaks: 1D value noise across the polish direction.
	float lane = v_uv.x * streak_scale;
	float streak = mix(hash11(floor(lane)), hash11(floor(lane) + 1.0), fract(lane));
	albedo *= 1.0 + (streak - 0.5) * 2.0 * streak_amount;
	// Honed edge line.
	albedo = mix(albedo, pow(edge_color.rgb, vec3(2.2)), v_edge);
	ALBEDO = albedo;
	METALLIC = 0.9;
	ROUGHNESS = 0.30;
	SPECULAR = 0.5;
	EMISSION += shadow_fill.rgb * fill_amount * albedo;
	// Fresnel sky sheen — code-only stand-in for reflection probes.
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += sky_tint.rgb * pow(fres, 2.0) * sky_amount * (0.4 + v_edge);
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float lit = smoothstep(band_lit_edge - band_soft, band_lit_edge + band_soft,
			ndl * ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * mix(shadow_tone, 1.0, lit);
	// The hot band: hard-stepped blinn lobe, slightly anisotropic (stretched
	// along the brush direction by flattening the normal contribution).
	vec3 h = normalize(normalize(VIEW) + normalize(LIGHT));
	float ndh = clamp(dot(normalize(NORMAL), h), 0.0, 1.0);
	float lobe = pow(ndh, spec_power);
	float hot = smoothstep(0.28, 0.36, lobe);
	float soft = smoothstep(0.04, 0.16, lobe) * 0.22;
	SPECULAR_LIGHT += LIGHT_COLOR * (hot * spec_strength + soft)
			* (1.0 + v_edge * 1.5) * ATTENUATION;
}
