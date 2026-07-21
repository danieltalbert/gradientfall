shader_type spatial;
render_mode specular_schlick_ggx;
// Kern's skin — cel-banded like the world (toon.gdshader family) but with the
// three things real skin does that flat toon misses: (1) a warm subsurface
// band exactly at the light terminator (blood under thin skin), (2) light
// leaking through thin features when backlit (ears, nose wings), and
// (3) pore-scale micro variation so close-ups don't read as plastic.
// Albedo = vertex COLOR (painted zones: cheek flush, knuckles, lip blend)
// times albedo_tint. No textures — everything analytic, per the code-only rule.

group_uniforms surface;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;

group_uniforms cel;
// Two-step band: deep shadow -> half tone -> lit. Positions in N.L space.
uniform float band_lit_edge : hint_range(-0.5, 0.9) = 0.10;
uniform float band_half_edge : hint_range(-0.9, 0.5) = -0.18;
uniform float band_soft : hint_range(0.005, 0.3) = 0.05;
uniform float half_tone : hint_range(0.0, 1.0) = 0.55;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.26;

group_uniforms subsurface;
uniform vec4 sss_color : source_color = vec4(0.82, 0.26, 0.15, 1.0);
uniform float sss_strength : hint_range(0.0, 1.5) = 0.40;
// Backlight transmission (ears / nostrils): strongest where the surface is
// thin. Thinness is authored in vertex COLOR.a (1 = thick, 0 = thin).
uniform float transmit_strength : hint_range(0.0, 2.0) = 0.30;

group_uniforms micro;
uniform float pore_amount : hint_range(0.0, 0.2) = 0.045;
uniform float pore_scale : hint_range(20.0, 400.0) = 150.0;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.18;
uniform float rim_width : hint_range(0.0, 1.0) = 0.74;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.05;

varying vec3 v_col;
varying float v_thick;
varying vec3 v_opos;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise3(vec3 p) {
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
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	v_thick = COLOR.a;
	v_opos = VERTEX;
}

void fragment() {
	vec3 albedo = v_col * albedo_tint.rgb * albedo_boost;
	// Pore/blotch micro variation in object space so it sticks to the skin.
	float pores = vnoise3(v_opos * pore_scale) * 0.55
			+ vnoise3(v_opos * pore_scale * 3.1) * 0.45;
	albedo *= 1.0 + (pores - 0.5) * 2.0 * pore_amount;
	ALBEDO = albedo;
	ROUGHNESS = 0.62;
	SPECULAR = 0.22;
	EMISSION += shadow_fill.rgb * fill_amount * albedo;
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += rim_color.rgb * smoothstep(rim_width, 1.0, fres) * rim_amount;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float shaded = ndl * ATTENUATION;
	// Two hard-ish steps, softened just enough to avoid pixel crawl.
	float lit = smoothstep(band_lit_edge - band_soft, band_lit_edge + band_soft, shaded);
	float half_lit = smoothstep(band_half_edge - band_soft * 2.0,
			band_half_edge + band_soft * 2.0, shaded);
	float tone = mix(shadow_tone, half_tone, half_lit);
	tone = mix(tone, 1.0, lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
	// Warm subsurface band riding the terminator: peaks where N.L crosses zero.
	float terminator = smoothstep(-0.34, -0.02, ndl) * (1.0 - smoothstep(0.02, 0.30, ndl));
	DIFFUSE_LIGHT += sss_color.rgb * sss_strength * terminator
			* LIGHT_COLOR / PI * ATTENUATION;
	// Backlight transmission through thin skin (ear glow against the sun).
	float back = clamp(dot(normalize(VIEW), -normalize(LIGHT)), 0.0, 1.0);
	float thin = 1.0 - v_thick;
	DIFFUSE_LIGHT += sss_color.rgb * pow(back, 3.0) * thin
			* transmit_strength * LIGHT_COLOR / PI * ATTENUATION;
	// A broad soft sheen so forehead/nose/cheekbones catch a live highlight.
	vec3 h = normalize(normalize(VIEW) + normalize(LIGHT));
	float spec = pow(clamp(dot(normalize(NORMAL), h), 0.0, 1.0), 24.0);
	SPECULAR_LIGHT += LIGHT_COLOR * spec * 0.10 * ATTENUATION * lit;
}
