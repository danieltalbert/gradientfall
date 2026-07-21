shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Mountain shader (richness pass 4) — toon_soft's soft-wrapped painterly base
// plus what rock at vista distance actually needs: world-space grain so faces
// never read as smooth putty, vertical erosion striations on the steeps, a
// glinting sparkle + tighter gloss on snow (COLOR.a carries the baked snow
// mask from gradient_peaks.gd), and a distance-haze assist that melts the far
// ranks into the sky beyond what uniform fog alone can do.

group_uniforms surface;
uniform bool use_srgb_vertex = true;
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.07;
uniform float rim_width : hint_range(0.0, 1.0) = 0.82;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.55, 0.68, 0.92, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.13;

group_uniforms rock;
// Two-scale world grain: breaks flat faces. Striations stretch the grain
// vertically on steep slopes — reads as erosion streaks / rock ribs.
uniform float grain_amount : hint_range(0.0, 0.3) = 0.10;
uniform float grain_scale : hint_range(0.001, 1.0) = 0.045;
uniform float striation_amount : hint_range(0.0, 0.3) = 0.12;

group_uniforms snow;
uniform float sparkle_amount : hint_range(0.0, 1.0) = 0.35;
uniform float sparkle_scale : hint_range(0.1, 8.0) = 1.6;
uniform float snow_gloss : hint_range(0.0, 1.0) = 0.55;

group_uniforms haze;
// Fragment-distance haze on top of the Environment fog: grounds the feet
// (full effect low) and lets summits stay crisp (fades with altitude).
uniform vec4 haze_color : source_color = vec4(0.72, 0.82, 0.9, 1.0);
uniform float haze_start = 900.0;
uniform float haze_full = 2200.0;
uniform float haze_max : hint_range(0.0, 0.6) = 0.22;
uniform float haze_top = 320.0;

varying vec3 v_col;
varying float v_snow;
varying vec3 v_wpos;

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
	v_col = use_srgb_vertex ? pow(COLOR.rgb, vec3(2.2)) : COLOR.rgb;
	v_snow = COLOR.a;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = v_col * albedo_boost;
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float steep = 1.0 - clamp(n_world.y, 0.0, 1.0);

	// Rock grain: two octaves of world-space value noise.
	float g = vnoise(v_wpos.xz * grain_scale) * 0.6
			+ vnoise(v_wpos.xz * grain_scale * 4.3) * 0.4;
	albedo *= 1.0 + (g - 0.5) * 2.0 * grain_amount * (1.0 - v_snow * 0.7);

	// Striations: grain stretched tall on the steeps — erosion ribs.
	float s = vnoise(vec2(v_wpos.x * 0.22 + v_wpos.z * 0.13, v_wpos.y * 0.035));
	albedo *= 1.0 + (s - 0.5) * 2.0 * striation_amount * steep * (1.0 - v_snow);

	ALBEDO = albedo;
	ROUGHNESS = mix(1.0, 1.0 - snow_gloss * 0.45, v_snow);
	SPECULAR = mix(0.15, 0.32, v_snow);

	// Sky-colored fill lifts shadow faces toward ambient — painted, not dead.
	EMISSION += shadow_fill.rgb * fill_amount * albedo;

	// Snow sparkle: thresholded high-frequency glints, snow only.
	float sp = hash21(floor(v_wpos.xz * sparkle_scale * 8.0));
	float glint = step(0.985, sp) * v_snow * sparkle_amount;
	EMISSION += vec3(1.0, 0.98, 0.92) * glint;

	// Fresnel rim, faint — a breath of sky on the silhouette edges.
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION += rim_color.rgb * smoothstep(rim_width, 1.0, fres) * rim_amount;

	// Distance haze assist, altitude-faded.
	float dist = length(VERTEX);
	float hz = smoothstep(haze_start, haze_full, dist) * haze_max;
	hz *= 1.0 - clamp(v_wpos.y / haze_top, 0.0, 0.85);
	ALBEDO = mix(ALBEDO, pow(haze_color.rgb, vec3(2.2)), hz);
}
