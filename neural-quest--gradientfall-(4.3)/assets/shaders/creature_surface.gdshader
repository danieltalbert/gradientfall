shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// High-frequency, texture-free creature material. Every meadow species uses
// real geometry for its silhouette and this shader for the final centimetres:
// guard-hair breakup, feather sheen, skin pebbling, horn rings, wetness, and
// restrained combat/variant illumination. It deliberately stays compatible
// with the project's procedural-asset pipeline—no imported texture dependency.

group_uniforms palette;
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 detail_color : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform float detail_mix : hint_range(0.0, 1.0) = 0.25;

group_uniforms pattern;
// 0 = organic noise, 1 = directional stripes, 2 = mottled spots,
// 3 = growth rings, 4 = feather/fur directional grain.
uniform int pattern_type : hint_range(0, 4) = 0;
uniform float pattern_scale : hint_range(0.5, 120.0) = 12.0;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.25;
uniform float micro_detail : hint_range(0.0, 0.5) = 0.12;
uniform float micro_bump : hint_range(0.0, 0.18) = 0.045;
uniform float seed_offset : hint_range(0.0, 100.0) = 0.0;

group_uniforms response;
uniform float surface_roughness : hint_range(0.05, 1.0) = 0.78;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.28;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float fuzz : hint_range(0.0, 1.0) = 0.2;
uniform float subsurface : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sheen_color : source_color = vec4(0.65, 0.75, 1.0, 1.0);
uniform vec4 shadow_fill : source_color = vec4(0.26, 0.38, 0.58, 1.0);
uniform float fill_amount : hint_range(0.0, 0.2) = 0.055;

group_uniforms gameplay;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float telegraph : hint_range(0.0, 1.0) = 0.0;
uniform float telegraph_gain : hint_range(0.0, 4.0) = 1.0;
uniform float corruption : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_pattern;

// Primitive meshes arrive as unit geometry and are scaled by their node,
// while custom lofts are already authored in metres. Per-instance metric
// correction keeps fur grain, skin pores, and horn rings at one physical size.
instance uniform vec3 pattern_metric = vec3(1.0);
instance uniform vec3 pattern_offset = vec3(0.0);


float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}


float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.07 + vec3(11.7, 4.3, 8.9);
		amplitude *= 0.48;
	}
	return total;
}


void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_pattern = VERTEX * pattern_metric + pattern_offset;
}


void fragment() {
	vec3 p = v_pattern * pattern_scale + vec3(seed_offset);
	float organic = fbm(p);
	float feature = organic;
	if (pattern_type == 1) {
		float bend = fbm(p * 0.24) * 2.2;
		feature = 0.5 + 0.5 * sin((v_pattern.z * 1.15 + v_pattern.y * 0.28) * pattern_scale + bend);
		feature = smoothstep(0.34, 0.66, feature);
	} else if (pattern_type == 2) {
		feature = smoothstep(0.56, 0.78, organic);
	} else if (pattern_type == 3) {
		float radius = length(v_pattern.xz);
		feature = 0.5 + 0.5 * sin(radius * pattern_scale * 3.14159 + organic * 1.8);
	} else if (pattern_type == 4) {
		float grain = 0.5 + 0.5 * sin((v_pattern.z * 2.4 + v_pattern.y * 0.35) * pattern_scale);
		feature = mix(grain, organic, 0.35);
	}

	float blend_amount = clamp(detail_mix + (feature - 0.5) * pattern_strength * 2.0, 0.0, 1.0);
	vec3 albedo = mix(base_color.rgb, detail_color.rgb, blend_amount);
	float micro_frequency = min(pattern_scale * 4.0, 150.0);
	float micro = fbm(v_pattern * micro_frequency + vec3(seed_offset * 0.37));
	albedo *= 1.0 + (micro - 0.5) * micro_detail;

	// Derivative-based height perturbation adds sub-centimetre feather barbs,
	// short coat and pebbled amphibian skin without texture assets or faceting.
	// It is screen-space stable, so the detail survives close 4K inspection.
	if (micro_bump > 0.0001) {
		vec3 base_normal = normalize(NORMAL);
		vec3 sigma_x = dFdx(v_world);
		vec3 sigma_y = dFdy(v_world);
		vec3 r1 = cross(sigma_y, base_normal);
		vec3 r2 = cross(base_normal, sigma_x);
		float det = dot(sigma_x, r1);
		if (abs(det) > 0.0000001) {
			vec3 gradient = sign(det) * (dFdx(micro) * r1 + dFdy(micro) * r2);
			// Screen derivatives are in world units and can be large on tiny,
			// life-sized animals. Keep the relief sub-millimetric instead of
			// turning every hair pore into a craggy foil facet.
			NORMAL = normalize(abs(det) * base_normal - gradient * micro_bump * 0.035);
		}
	}

	// Corruption is deliberately veined rather than a full-body recolor.
	if (corruption > 0.001) {
		float veins = smoothstep(0.72, 0.9, fbm(v_pattern * 18.0 + vec3(seed_offset)));
		albedo = mix(albedo, vec3(0.16, 0.035, 0.25), veins * corruption * 0.8);
	}

	ALBEDO = mix(albedo, vec3(1.0), hit_flash * 0.82);
	// Moisture retains a rough organic substrate instead of turning skin into
	// lacquered plastic; the wet film strengthens specular without erasing pores.
	ROUGHNESS = mix(surface_roughness, 0.24, wetness * 0.72);
	SPECULAR = mix(surface_specular, 0.9, wetness);
	METALLIC = surface_metallic;
	SSS_STRENGTH = subsurface;

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 edge_sheen = sheen_color.rgb * fresnel * fuzz * (0.08 + wetness * 0.12);
	vec3 combat_glow = mix(vec3(1.0, 0.36, 0.12), vec3(0.76, 0.34, 1.0), corruption);
	// A restrained sky fill keeps dense muzzles, chests, and folded feathers
	// readable without flattening the direct-light modelling.
	EMISSION = albedo * fill_amount + shadow_fill.rgb * albedo * fill_amount * 0.45
			+ edge_sheen + combat_glow * telegraph * telegraph_gain * (0.16 + fresnel * 0.22);
}
