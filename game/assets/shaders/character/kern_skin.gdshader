shader_type spatial;
render_mode specular_schlick_ggx;
// Kern's skin — pushed toward realism (Danny's "look like a real face" bar).
// Instead of hard toon banding, skin uses: smooth wrapped diffuse with a
// separate wider, red-shifted subsurface wrap that reddens the terminator the
// way blood under thin skin does; a fine procedural detail-normal (Mikkelsen
// screen-space derivative bump from object-space noise) that breaks up the
// specular into skin-like micro-shadow; a dual-lobe specular (broad oily sheen
// + tight highlight) on a ~0.5 roughness; backlight transmission through thin
// features (ears/nostrils, authored in COLOR.a); and crease occlusion baked
// straight into the albedo at build time. A whisper of cool rim keeps Kern
// reading against the world without the plastic blue edge.

group_uniforms surface;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;
uniform float roughness_base : hint_range(0.2, 0.9) = 0.52;

group_uniforms subsurface;
uniform vec4 sss_color : source_color = vec4(0.72, 0.20, 0.12, 1.0);
uniform float sss_strength : hint_range(0.0, 2.0) = 0.85;
uniform float diffuse_wrap : hint_range(0.0, 1.0) = 0.35;
uniform float sss_wrap : hint_range(0.0, 1.5) = 0.85;
uniform float transmit_strength : hint_range(0.0, 2.0) = 0.55;

group_uniforms micro;
// Two scales of pore/wrinkle bump. Object-space so it sticks to the skin.
// bump_strength is in metres of virtual height — skin micro-relief is sub-
// millimetre, so this stays tiny; the derivative bump amplifies it plenty.
uniform float bump_strength : hint_range(0.0, 0.01) = 0.0;
uniform float pore_scale : hint_range(20.0, 600.0) = 380.0;
uniform float pore_depth : hint_range(0.0, 2.0) = 0.5;
uniform float wrinkle_scale : hint_range(4.0, 120.0) = 110.0;
uniform float wrinkle_depth : hint_range(0.0, 2.0) = 0.25;

group_uniforms spec;
uniform float spec_broad : hint_range(0.0, 1.0) = 0.06;
uniform float spec_tight : hint_range(0.0, 1.0) = 0.16;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.66, 0.80, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.12;
uniform float rim_width : hint_range(0.0, 1.0) = 0.78;

group_uniforms magic;
// As the First Model surfaces, a signature glow rides Kern's silhouette and
// breaks into flickering data-shards of light at the very edge.
uniform float awaken : hint_range(0.0, 1.0) = 0.12;
uniform vec4 glow_color : source_color = vec4(1.0, 0.74, 0.28, 1.0);

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.30, 0.40, 0.62, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.06;

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

// Height field for the bump (metres): fine pores plus coarser wrinkle grain.
float skin_height(vec3 p) {
	float pores = (vnoise3(p * pore_scale) - 0.5) * pore_depth;
	float wr = (vnoise3(p * wrinkle_scale) - 0.5) * wrinkle_depth;
	return (pores + wr) * bump_strength;
}

void vertex() {
	v_col = pow(COLOR.rgb, vec3(2.2));
	v_thick = COLOR.a;
	v_opos = VERTEX;
}

void fragment() {
	ALBEDO = v_col * albedo_tint.rgb * albedo_boost;
	ROUGHNESS = roughness_base;
	SPECULAR = 0.28;

	// Mikkelsen derivative bump: perturb the shading normal from the
	// object-space skin height field (works on unparametrised meshes).
	float h = skin_height(v_opos);
	vec3 vP = VERTEX;
	vec3 sigmaS = dFdx(vP);
	vec3 sigmaT = dFdy(vP);
	vec3 vN = normalize(NORMAL);
	vec3 vR1 = cross(sigmaT, vN);
	vec3 vR2 = cross(vN, sigmaS);
	float fDet = dot(sigmaS, vR1);
	float dBs = dFdx(h);
	float dBt = dFdy(h);
	vec3 grad = sign(fDet) * (dBs * vR1 + dBt * vR2);
	NORMAL = normalize(abs(fDet) * vN - grad);

	EMISSION += shadow_fill.rgb * fill_amount * ALBEDO;
	float fres = 1.0 - clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0);
	EMISSION += rim_color.rgb * smoothstep(rim_width, 1.0, fres) * rim_amount;
	// Charged: a whisper of warmth on the extreme silhouette only. Kept tiny —
	// a fresnel glow floods rounded limbs, so the mark, threads, eyes and
	// orbiting shards carry the visible magic, not the skin.
	EMISSION += glow_color.rgb * smoothstep(0.94, 1.0, fres) * awaken * 0.10;
}

void light() {
	vec3 N = normalize(NORMAL);
	vec3 L = normalize(LIGHT);
	float ndl = dot(N, L);
	// Wrapped diffuse: soft terminator instead of a hard toon step.
	float diff = clamp((ndl + diffuse_wrap) / (1.0 + diffuse_wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * diff * ATTENUATION;
	// Subsurface: a wider wrap, and the light that lives only in that wider
	// band (sss - diff) gets tinted red — the glow just past the terminator.
	float sss = clamp((ndl + sss_wrap) / (1.0 + sss_wrap), 0.0, 1.0);
	sss = pow(sss, 1.4);
	float band = max(0.0, sss - diff);
	DIFFUSE_LIGHT += sss_color.rgb * ALBEDO * band * sss_strength
			* LIGHT_COLOR * ATTENUATION;
	// Backlight transmission through thin skin (ears / nostrils / lips edge).
	float back = clamp(dot(normalize(VIEW), -L), 0.0, 1.0);
	float thin = 1.0 - v_thick;
	DIFFUSE_LIGHT += sss_color.rgb * pow(back, 2.5) * thin
			* transmit_strength * LIGHT_COLOR * ATTENUATION;
	// Dual-lobe skin specular on the bumped normal: a broad oily sheen and a
	// tighter highlight, both gated so the dark side stays matte.
	vec3 H = normalize(normalize(VIEW) + L);
	float ndh = clamp(dot(N, H), 0.0, 1.0);
	float lit = clamp(ndl * 2.0, 0.0, 1.0);
	float broad = pow(ndh, 18.0) * spec_broad;
	float tight = pow(ndh, 90.0) * spec_tight;
	SPECULAR_LIGHT += LIGHT_COLOR * (broad + tight) * lit * ATTENUATION;
}
