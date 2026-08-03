shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Bark, rebuilt 2026-08-03. Danny: "it needs more detail for the wood, some way
// to look like a real tree instead of different colored lines."
//
// That was the exact defect. The old version drew sin() ridges into ALBEDO and
// never touched NORMAL, so the trunk was a flat cylinder with stripes painted
// on it — paint, not wood. Light could not find a single ridge because from the
// renderer's point of view the surface was perfectly smooth.
//
// What it does now:
//   * a real bark HEIGHT FIELD — domain-warped ridged fissures that wander and
//     fork, riding on broader plates, with fine grain on top
//   * that height drives the shading normal through the same Mikkelsen
//     screen-space derivative bump `kern_skin.gdshader` uses, so the geometry
//     stays a cheap cylinder while the light behaves as if it were carved
//   * albedo, occlusion and roughness all read from the SAME height, so the
//     colour of a fissure agrees with its shape instead of being a second,
//     unrelated pattern
//   * seamless around the trunk: the noise is sampled on a ring
//     (cos, sin, height) rather than on UV.x, which has a wrap seam

group_uniforms color;
uniform vec4 bark_color : source_color = vec4(0.40, 0.30, 0.205, 1.0);
uniform vec4 bark_light : source_color = vec4(0.575, 0.455, 0.315, 1.0);
uniform vec4 groove_color : source_color = vec4(0.135, 0.093, 0.058, 1.0);
uniform vec4 moss_color : source_color = vec4(0.20, 0.31, 0.11, 1.0);
// A trunk stands under its own canopy, the densest shadow caster in the meadow,
// and Godot multiplies ambient by albedo down to nearly nothing — which is why
// bark rendered near-black in daylight. Tuned by render: 0.34 overcorrected
// into glowing terracotta, which is worse, because at least a black trunk does
// not look lit from inside.
uniform float ambient_floor : hint_range(0.0, 2.0) = 0.15;
uniform vec4 ambient_floor_tint : source_color = vec4(1.0, 0.90, 0.78, 1.0);

group_uniforms relief;
// Virtual relief in metres. Real bark fissures on a mature broadleaf run
// 10-25 mm deep; the derivative bump reads that plenty at arm's length.
uniform float bump_strength : hint_range(0.0, 0.12) = 0.022;
// How many fissures run around the trunk. Higher = finer, younger-looking bark.
uniform float fissure_scale : hint_range(1.0, 30.0) = 8.5;
// Vertical stretch. Bark features are far longer than they are wide, and this
// ratio is most of what separates bark from generic rock noise.
uniform float vertical_stretch : hint_range(0.02, 1.0) = 0.16;
uniform float plate_scale : hint_range(0.5, 12.0) = 3.4;
uniform float grain_scale : hint_range(4.0, 80.0) = 34.0;

group_uniforms wind;
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.05;
uniform float tree_height = 9.0;

varying vec2 v_uv;
varying vec3 v_world_position;
varying vec3 v_local_position;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 3D value noise. Sampled on a ring so it wraps around the trunk with no seam.
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

float fbm3(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += vnoise3(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// The bark surface, in metres of relief above the mean.
//
// Three layers, in the order real bark forms them: deep fissures that split the
// cambium as the trunk grows, broad plates between them, and fine grain over
// everything. The fissures are DOMAIN-WARPED, which is what makes them wander
// and fork instead of running as parallel stripes — the single difference
// between "bark" and "corduroy".
float bark_height(vec3 q) {
	// Warp hard. At 1.7 the fissures still ran near-parallel and the trunk read
	// as bamboo or a bundle of cables; bark only stops looking like corduroy
	// once the warp is strong enough to make creases genuinely wander and fork.
	float warp = fbm3(q * vec3(1.1, 1.1, 0.26)) * 2.9;
	vec3 warped = q + vec3(warp, warp, warp * 0.42);
	float fissure = fbm3(warped * vec3(fissure_scale, fissure_scale,
			fissure_scale * vertical_stretch));
	// Ridge transform: the creases become sharp valleys, the rest stays broad.
	fissure = 1.0 - abs(fissure * 2.0 - 1.0);
	fissure = pow(clamp(fissure, 0.0, 1.0), 2.3);

	// Cross-cracks: the same ridge trick with the stretch INVERTED, so these run
	// around the trunk instead of up it. Their intersection with the vertical
	// fissures is what breaks bark into plates rather than staves — without
	// them no amount of warping stops it reading as a bundle of rods.
	float cross_warp = fbm3(q * vec3(0.7, 0.7, 1.9)) * 1.4;
	float cross_crack = fbm3((q + vec3(cross_warp)) * vec3(
			fissure_scale * 0.34, fissure_scale * 0.34, fissure_scale * 1.15));
	cross_crack = 1.0 - abs(cross_crack * 2.0 - 1.0);
	cross_crack = pow(clamp(cross_crack, 0.0, 1.0), 3.4);

	float plates = fbm3(q * vec3(plate_scale, plate_scale,
			plate_scale * vertical_stretch * 2.2));
	float grain = vnoise3(q * vec3(grain_scale, grain_scale,
			grain_scale * vertical_stretch * 3.0));
	float height = fissure * 0.50 + plates * 0.26 + grain * 0.11;
	// Cross-cracks CUT, so they subtract rather than add.
	return clamp(height - cross_crack * 0.30 + 0.13, 0.0, 1.0);
}

void vertex() {
	v_uv = UV;
	vec3 initial_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_direction = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	vec2 local_direction = normalize(vec2(
		dot(world_direction, model_x), dot(world_direction, model_z)
	));
	float march = dot(initial_world.xz, normalize(wind_dir)) * 0.045 - TIME * wind_speed;
	float gust = smoothstep(-0.62, 0.8, sin(march));
	gust *= gust;
	float height_weight = smoothstep(0.28, 0.92, clamp(VERTEX.y / tree_height, 0.0, 1.0));
	float branch_weight = smoothstep(0.32, 1.5, length(VERTEX.xz));
	VERTEX.xz += local_direction * gust * 0.07 * height_weight * branch_weight;
	v_local_position = VERTEX;
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Sample on a ring rather than on UV.x. UV.x has a wrap seam at 0/1, and a
	// noise sampled across it draws a visible stripe straight up every trunk.
	float angle = v_uv.x * 6.2831853;
	vec3 ring = vec3(cos(angle), sin(angle), v_local_position.y);

	float height = bark_height(ring);

	// Albedo from the same height that shapes the surface: deep fissures are
	// dark and damp, raised plates catch light. Because both come from one
	// field, the colour of a crease always agrees with its shape.
	vec3 color = mix(groove_color.rgb, bark_color.rgb,
			smoothstep(0.12, 0.55, height));
	color = mix(color, bark_light.rgb, smoothstep(0.55, 0.92, height) * 0.85);
	// Slow tonal drift so neighbouring trunks are not the same brown.
	float drift = fbm3(v_world_position * 0.31);
	color *= 0.88 + drift * 0.26;

	// Moss on the low, shaded side. Real moss grows where damp sits, which is
	// the bottom of the trunk and inside the fissures, so it is gated on both.
	float low_trunk = 1.0 - smoothstep(1.1, 4.6, max(v_local_position.y, 0.0));
	float damp = 1.0 - smoothstep(0.15, 0.5, height);
	float moss = smoothstep(0.52, 0.86, fbm3(v_world_position * 0.62 + vec3(9.0, -13.0, 4.0)));
	color = mix(color, moss_color.rgb, moss * low_trunk * (0.22 + damp * 0.3));

	ALBEDO = color;

	// Mikkelsen screen-space derivative bump — the same one kern_skin uses. It
	// perturbs the shading normal from the height field without needing
	// tangents, so the cylinder keeps its cheap geometry and gains carved light.
	float h = height * bump_strength;
	vec3 position = VERTEX;
	vec3 sigma_s = dFdx(position);
	vec3 sigma_t = dFdy(position);
	vec3 base_normal = normalize(NORMAL);
	vec3 r1 = cross(sigma_t, base_normal);
	vec3 r2 = cross(base_normal, sigma_s);
	float determinant = dot(sigma_s, r1);
	vec3 gradient = sign(determinant) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(determinant) * base_normal - gradient);

	// Fissures self-occlude: light does not reach the bottom of a 2 cm crack.
	float occlusion = mix(0.55, 1.0, smoothstep(0.05, 0.5, height));
	AO = occlusion;
	AO_LIGHT_AFFECT = 0.75;

	// Deep bark is damp and matte; raised plates are weathered and slightly
	// less so. Wood is never glossy, so the whole range stays high.
	ROUGHNESS = mix(0.97, 0.80, smoothstep(0.2, 0.85, height));
	SPECULAR = 0.14;
	EMISSION = color * ambient_floor_tint.rgb * ambient_floor * occlusion;
	RIM = 0.06;
	RIM_TINT = 0.3;
}
