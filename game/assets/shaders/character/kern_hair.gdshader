shader_type spatial;
render_mode specular_schlick_ggx;
// Hair for Kern's clump-built haircut and eyebrows. Each clump is a tapered
// loft with UV.y = root(0) -> tip(1), UV.x = around the clump, so the shader
// can do the three things stylized-real hair needs: a root->tip albedo ramp
// (dark at scalp, sun-warmed at tips), a Kajiya-Kay anisotropic sheen band
// that follows the strand direction (TANGENT runs along the clump from the
// loft), and per-clump value variation via COLOR so the cut reads as many
// locks, not one brown helmet.

group_uniforms color;
uniform vec4 root_color : source_color = vec4(0.16, 0.09, 0.05, 1.0);
uniform vec4 tip_color : source_color = vec4(0.42, 0.26, 0.12, 1.0);
uniform float ramp_bias : hint_range(0.2, 3.0) = 1.4;

group_uniforms strands;
uniform float strand_scale : hint_range(4.0, 120.0) = 34.0;
uniform float strand_amount : hint_range(0.0, 0.4) = 0.16;

group_uniforms cel;
uniform float band_lit_edge : hint_range(-0.5, 0.9) = 0.14;
uniform float band_soft : hint_range(0.005, 0.3) = 0.07;
uniform float half_tone : hint_range(0.0, 1.0) = 0.52;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.26;

group_uniforms sheen;
uniform vec4 sheen_color : source_color = vec4(0.95, 0.78, 0.52, 1.0);
uniform float sheen_power : hint_range(8.0, 260.0) = 180.0;
uniform float sheen_strength : hint_range(0.0, 2.0) = 0.34;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.18;
uniform float rim_width : hint_range(0.0, 1.0) = 0.70;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.06;

varying vec3 v_col;
varying vec2 v_uv;
// TANGENT is not available in light(); stash the view-space strand direction
// from fragment() into a varying (Godot allows fragment-assigned varyings to
// be read in light()).
varying vec3 v_tangent;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	v_uv = UV;
}

void fragment() {
	float along = pow(clamp(v_uv.y, 0.0, 1.0), ramp_bias);
	vec3 albedo = mix(pow(root_color.rgb, vec3(2.2)),
			pow(tip_color.rgb, vec3(2.2)), along);
	albedo *= v_col;  // per-clump variation painted at build time
	// Strand striations running along the clump.
	float lane = v_uv.x * strand_scale;
	float strand = mix(hash21(vec2(floor(lane), 0.0)),
			hash21(vec2(floor(lane) + 1.0, 0.0)), fract(lane));
	albedo *= 1.0 + (strand - 0.5) * 2.0 * strand_amount;
	v_tangent = normalize(TANGENT);
	ALBEDO = albedo;
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
	EMISSION += shadow_fill.rgb * fill_amount * albedo;
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += rim_color.rgb * smoothstep(rim_width, 1.0, fres) * rim_amount;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float shaded = ndl * ATTENUATION;
	float lit = smoothstep(band_lit_edge - band_soft, band_lit_edge + band_soft, shaded);
	float half_lit = smoothstep(-0.30, -0.10, shaded);
	float tone = mix(shadow_tone, half_tone, half_lit);
	tone = mix(tone, 1.0, lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
	// Kajiya-Kay: highlight follows the strand tangent, not the normal —
	// this is the arc of light that slides over hair as the head turns.
	vec3 t = normalize(v_tangent);
	vec3 h = normalize(normalize(VIEW) + normalize(LIGHT));
	float th = dot(t, h);
	float sin_th = sqrt(max(0.0, 1.0 - th * th));
	float sheen = pow(sin_th, sheen_power);
	float band = smoothstep(0.72, 0.9, sheen);
	SPECULAR_LIGHT += sheen_color.rgb * LIGHT_COLOR * band
			* sheen_strength * ATTENUATION * max(lit, 0.2);
}
