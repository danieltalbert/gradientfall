shader_type spatial;
render_mode specular_schlick_ggx;
// Woven cloth for Kern's tunic / trousers / cloak / scarf. What sells fabric
// at arm's length: a visible thread weave (two perpendicular yarn directions
// with a twill diagonal), yarn-dye value variation so panels aren't flat,
// a fuzzy peach-lint rim instead of a glossy one, and sun bleeding through
// the weave when backlit (thin cloth glows). UVs come from the garment lofts
// (x = around, y = along the garment); COLOR carries painted weathering.
// COLOR.a = looseness (0 pinned at seams -> 1 free hem) driving micro-flutter.

group_uniforms surface;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;

group_uniforms weave;
uniform float weave_scale : hint_range(10.0, 600.0) = 190.0;
uniform float weave_amount : hint_range(0.0, 0.4) = 0.13;
uniform float yarn_amount : hint_range(0.0, 0.4) = 0.10;

group_uniforms cel;
uniform float band_lit_edge : hint_range(-0.5, 0.9) = 0.12;
uniform float band_half_edge : hint_range(-0.9, 0.5) = -0.16;
uniform float band_soft : hint_range(0.005, 0.3) = 0.06;
uniform float half_tone : hint_range(0.0, 1.0) = 0.52;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.24;

group_uniforms backlight;
uniform float transmit_strength : hint_range(0.0, 1.5) = 0.28;
uniform vec4 transmit_tint : source_color = vec4(1.0, 0.86, 0.62, 1.0);

group_uniforms motion;
// Tiny breathing flutter for free edges; the big motion is bone-driven.
uniform float flutter_amount : hint_range(0.0, 0.05) = 0.0;
uniform float flutter_speed : hint_range(0.0, 8.0) = 2.6;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.34;
uniform float rim_width : hint_range(0.0, 1.0) = 0.58;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.10;

varying vec3 v_col;
varying vec2 v_uv;
varying float v_loose;

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

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	v_uv = UV;
	v_loose = COLOR.a;
	if (flutter_amount > 0.0001) {
		float w = sin(TIME * flutter_speed + UV.x * 9.0 + UV.y * 5.0)
				* sin(TIME * flutter_speed * 0.73 + UV.y * 13.0);
		VERTEX += NORMAL * w * flutter_amount * v_loose;
	}
}

void fragment() {
	vec3 albedo = v_col * albedo_tint.rgb * albedo_boost;
	// Twill weave: warp threads, weft threads, and the diagonal step that
	// makes it read as cloth instead of a printed grid.
	vec2 wuv = v_uv * weave_scale;
	float diag = floor(fract((wuv.x + wuv.y) * 0.25) * 2.0);
	float warp = sin(wuv.x * 6.2831853) * 0.5 + 0.5;
	float weft = sin(wuv.y * 6.2831853 + diag * 3.14159) * 0.5 + 0.5;
	float weave = mix(warp, weft, 0.5) - 0.5;
	albedo *= 1.0 + weave * 2.0 * weave_amount;
	// Yarn-dye blotches: two octaves of low-frequency value drift.
	float yarn = vnoise(v_uv * 7.0) * 0.6 + vnoise(v_uv * 23.0) * 0.4;
	albedo *= 1.0 + (yarn - 0.5) * 2.0 * yarn_amount;
	ALBEDO = albedo;
	ROUGHNESS = 0.95;
	SPECULAR = 0.06;
	EMISSION += shadow_fill.rgb * fill_amount * albedo;
	// Fuzz rim: wider and softer than skin/metal — lint catching light.
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(rim_width, 1.0, fres);
	EMISSION += mix(rim_color.rgb, albedo * 2.2, 0.45) * rim * rim_amount;
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
	// Sun through the weave on free (thin, single-layer) parts of the garment.
	float back = clamp(dot(normalize(VIEW), -normalize(LIGHT)), 0.0, 1.0);
	DIFFUSE_LIGHT += transmit_tint.rgb * ALBEDO * pow(back, 2.5)
			* transmit_strength * v_loose * LIGHT_COLOR / PI * ATTENUATION;
}
