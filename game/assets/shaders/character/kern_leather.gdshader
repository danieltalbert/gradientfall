shader_type spatial;
render_mode specular_schlick_ggx;
// Leather for belt, boots, grip wrap, scabbard, pouch. Real leather reads as:
// a fine pebbled grain (two scales of cellular-ish noise), a satin band of
// specular that's tighter than cloth but far from metal, and — the detail
// that says "worn, not new" — burnished lightening along handled edges.
// Edge wear is authored per-vertex in COLOR.a (0 = fresh dye, 1 = worn).

group_uniforms surface;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;
uniform vec4 worn_color : source_color = vec4(0.78, 0.60, 0.38, 1.0);

group_uniforms grain;
uniform float grain_scale : hint_range(30.0, 900.0) = 320.0;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.10;

group_uniforms cel;
uniform float band_lit_edge : hint_range(-0.5, 0.9) = 0.10;
uniform float band_half_edge : hint_range(-0.9, 0.5) = -0.18;
uniform float band_soft : hint_range(0.005, 0.3) = 0.05;
uniform float half_tone : hint_range(0.0, 1.0) = 0.50;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.22;

group_uniforms sheen;
uniform float sheen_power : hint_range(2.0, 120.0) = 34.0;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.30;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.26;
uniform float rim_width : hint_range(0.0, 1.0) = 0.66;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.09;

varying vec3 v_col;
varying vec3 v_opos;
varying float v_wear;

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
	v_opos = VERTEX;
	v_wear = COLOR.a;
}

void fragment() {
	vec3 albedo = v_col * albedo_tint.rgb * albedo_boost;
	// Pebbled grain: ridges between noise cells, two octaves.
	float g1 = vnoise3(v_opos * grain_scale);
	float g2 = vnoise3(v_opos * grain_scale * 2.7 + 13.7);
	float grain = abs(g1 - 0.5) * 1.2 + abs(g2 - 0.5) * 0.8;
	albedo *= 1.0 - grain * grain_amount * 2.0;
	// Burnished wear: dye rubbed through to the pale hide beneath.
	albedo = mix(albedo, pow(worn_color.rgb, vec3(2.2)),
			v_wear * (0.55 + g1 * 0.45));
	ALBEDO = albedo;
	ROUGHNESS = mix(0.72, 0.45, v_wear);  // handled leather polishes up
	SPECULAR = 0.25;
	EMISSION += shadow_fill.rgb * fill_amount * albedo;
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += rim_color.rgb * smoothstep(rim_width, 1.0, fres) * rim_amount;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float shaded = ndl * ATTENUATION;
	float lit = smoothstep(band_lit_edge - band_soft, band_lit_edge + band_soft, shaded);
	float half_lit = smoothstep(band_half_edge - band_soft * 2.0,
			band_half_edge + band_soft * 2.0, shaded);
	float tone = mix(shadow_tone, half_tone, half_lit);
	tone = mix(tone, 1.0, lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
	// Satin band — brighter on worn (burnished) areas.
	vec3 h = normalize(normalize(VIEW) + normalize(LIGHT));
	float spec = pow(clamp(dot(normalize(NORMAL), h), 0.0, 1.0), sheen_power);
	float band = smoothstep(0.18, 0.30, spec);
	SPECULAR_LIGHT += LIGHT_COLOR * band * sheen_strength
			* (0.6 + v_wear * 0.8) * ATTENUATION * lit;
}
