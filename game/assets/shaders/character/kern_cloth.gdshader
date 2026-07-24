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
// Kept low: too much and thin garment edges read as see-through gauze rather
// than cloth catching a little sun through the weave.
uniform float transmit_strength : hint_range(0.0, 1.5) = 0.12;
uniform vec4 transmit_tint : source_color = vec4(1.0, 0.86, 0.62, 1.0);

group_uniforms motion;
// Wind: a travelling gust wave along wind_dir plus finer flutter, weighted by
// looseness (COLOR.a) so seams stay put and free hems/sleeves/scarf ripple.
uniform float wind_strength : hint_range(0.0, 0.06) = 0.0;
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.35);
uniform float wind_speed : hint_range(0.0, 6.0) = 1.7;

group_uniforms trim;
// Embroidered border: a perceptron glyph — nodes wired together — drawn in one
// or two UV.y bands (each vec2 = centre_v, half_height; negative centre = off).
// Echoes the game's icon, and glows with `awaken` (charged embroidery).
uniform vec4 trim_color : source_color = vec4(0.86, 0.70, 0.30, 1.0);
uniform vec4 trim_color2 : source_color = vec4(0.62, 0.24, 0.16, 1.0);
uniform float trim_reps : hint_range(2.0, 80.0) = 20.0;
uniform vec2 trim_band_a = vec2(-1.0, 0.05);
uniform vec2 trim_band_b = vec2(-1.0, 0.05);

group_uniforms magic;
uniform float awaken : hint_range(0.0, 1.0) = 0.12;
uniform vec4 trim_glow_color : source_color = vec4(1.0, 0.72, 0.24, 1.0);

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.20;
uniform float rim_width : hint_range(0.0, 1.0) = 0.64;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.07;

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
	if (wind_strength > 0.00001 && v_loose > 0.001) {
		vec3 wd = normalize(wind_dir);
		float phase = dot(VERTEX, wd) * 6.0 - TIME * wind_speed * 2.4;
		float gust = sin(phase) * 0.6 + sin(phase * 1.9 + 1.3) * 0.4;
		float flutter = sin(TIME * wind_speed * 3.4 + UV.x * 20.0 + UV.y * 12.0) * 0.5
				+ sin(TIME * wind_speed * 5.1 + UV.x * 34.0) * 0.3;
		float amt = wind_strength * v_loose * v_loose;
		// Billow with the wind, and ripple along the surface normal.
		VERTEX += wd * (gust * 0.5 + 0.5) * amt;
		VERTEX += NORMAL * (gust * 0.35 + flutter * 0.5) * amt;
	}
}

// Perceptron-glyph trim inside one UV.y band; returns node/wire coverage 0..1.
// A repeating cell holds a centre node, two flanking nodes, wires between them,
// and border rails top & bottom.
float trim_mask(vec2 uv, vec2 band) {
	if (band.x < 0.0) {
		return 0.0;
	}
	float lv = (uv.y - band.x) / band.y;   // -1..1 across the band
	if (abs(lv) > 1.0) {
		return 0.0;
	}
	// Border rails.
	float rails = step(0.82, abs(lv));
	// Repeating cell along the band.
	float cx = fract(uv.x * trim_reps) - 0.5;   // -0.5..0.5 within a cell
	// Centre node + two side nodes (on the rails-inward line lv ~ 0).
	float centre = step(length(vec2(cx, lv * 0.9)), 0.16);
	float side = step(length(vec2(abs(cx) - 0.42, lv * 0.9)), 0.10);
	// Wires: a horizontal spine plus diagonal links from centre to side nodes.
	float spine = step(abs(lv), 0.10) * step(abs(cx), 0.46);
	float diag = step(abs(abs(lv) - abs(cx) * 1.8), 0.08) * step(abs(cx), 0.42);
	return clamp(rails + centre + side + spine + diag, 0.0, 1.0);
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
	// Embroidered perceptron-glyph trim: rails in the accent colour, nodes/wires
	// in gold; the whole band glows as Kern awakens.
	float t_a = trim_mask(v_uv, trim_band_a);
	float t_b = trim_mask(v_uv, trim_band_b);
	float trim = clamp(t_a + t_b, 0.0, 1.0);
	if (trim > 0.001) {
		float lv_a = trim_band_a.x < 0.0 ? 2.0 : abs((v_uv.y - trim_band_a.x) / trim_band_a.y);
		float lv_b = trim_band_b.x < 0.0 ? 2.0 : abs((v_uv.y - trim_band_b.x) / trim_band_b.y);
		float lv = min(lv_a, lv_b);
		float is_rail = step(0.82, lv);
		vec3 tc = mix(trim_color.rgb, trim_color2.rgb, is_rail);
		albedo = mix(albedo, tc, trim);
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
	EMISSION += shadow_fill.rgb * fill_amount * albedo;
	// Charged embroidery: only the glyph itself lights up as awaken rises — the
	// discrete threads/nodes glow, so the cloth around them stays its true
	// colour (a fresnel "edge" glow floods rounded cloth and was dropped).
	EMISSION += trim_glow_color.rgb * trim * (0.03 + awaken * 0.55);
	// Fuzz rim: soft lint catching light.
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
