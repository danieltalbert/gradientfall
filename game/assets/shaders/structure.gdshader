shader_type spatial;
// Surface shader for authored .glb buildings (docs/STRUCTURE_PIPELINE.md).
//
// WHY THIS EXISTS
// The 2026-08-09 survey found Bootstrap reading as a prototype at eye level.
// Geometry was half the diagnosis; the other half was that every surface in
// the town was ONE FLAT COLOUR. A wall with a single albedo and a constant
// normal has no information in it at any distance — it is the visual
// equivalent of a solid fill, and no amount of modelling rescues it.
//
// The fix here is procedural, not textures, and that is deliberate: this
// project has no texture files at all (see toon.gdshader) and every other
// surface in the world — bark, grass, terrain, water, cloud — is generated in
// a shader. A .glb of imported maps would be the one exception in the
// codebase, would need provenance tracking, and would tile visibly on a
// nine-metre wall. Noise costs nothing, never seams, and is authored in the
// same place as the rest of the look.
//
// One shader serves every material group; `kind` selects the pattern, because
// what actually differs between plaster and oak is the noise, not the lighting
// model. Node-name -> kind mapping lives in structure_asset.gd.
//
//   0 PLASTER  lime render: broad stain, fine tooth, soft bump
//   1 TIMBER   oak: grain stretched along the member, hard darks in the grain
//   2 TILE     clay: per-tile colour variation, quantised on the tile grid
//   3 STONE    rubble: per-stone tone, coarse pitting
//   4 METAL    wrought iron: near-flat, slightly rough, dark
//   5 GLASS    leaded pane: dark, smooth, a little reflective

render_mode specular_schlick_ggx;

group_uniforms surface;
uniform vec4 albedo_tint : source_color = vec4(0.8, 0.78, 0.7, 1.0);
uniform int kind : hint_range(0, 5) = 0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;

group_uniforms detail;
// Metres per repeat of the coarse pattern. Everything is driven off object
// space, so a building keeps its grain when the town moves it.
uniform float pattern_scale : hint_range(0.1, 8.0) = 1.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;
uniform float value_variation : hint_range(0.0, 0.6) = 0.16;
// Tile/stone unit size, for the quantised per-unit tint. x is across the
// course, y is the course height, and both must match what the Blender build
// script laid down or the tint grid will cut across the units.
uniform vec2 unit_size = vec2(0.225, 0.128);

group_uniforms night;
// Hearthlight behind the glass. BootstrapTown drives this from the sky cycle
// exactly as it drives the code-built buildings' windows — an authored .glb
// must not opt out of the town's day/night behaviour just because its meshes
// came from Blender.
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.36, 1.0);
uniform float window_glow : hint_range(0.0, 4.0) = 0.0;

group_uniforms weathering;
// Dirt collects where rain cannot wash it: under sills, in the lee of beams,
// and along the bottom of a wall. Driven by object-space height plus a
// downward-facing term, which is a cheap stand-in for real cavity occlusion.
uniform vec4 grime_color : source_color = vec4(0.30, 0.27, 0.22, 1.0);
uniform float grime_amount : hint_range(0.0, 1.0) = 0.30;
uniform float grime_height : hint_range(0.1, 8.0) = 1.4;

varying vec3 v_obj;
varying vec3 v_wnormal;

// --- noise -----------------------------------------------------------------

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += vnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// --- per-kind height field --------------------------------------------------
//
// One scalar per kind, used for BOTH the albedo break-up and the normal
// perturbation, so the light and the colour agree about where the surface is
// low. That agreement is most of what sells a material.

float surface_height(vec3 p) {
	if (kind == 1) {
		// Oak. Grain is strongly anisotropic: squash across the member and
		// stretch along it. The member's long axis is unknown here, so the
		// grain is laid along whichever object axis the face is least aligned
		// with — for an axis-aligned frame that is always the run.
		vec3 g = abs(v_wnormal);
		vec3 q = (g.x > g.y && g.x > g.z) ? p.zyx : ((g.y > g.z) ? p.xzy : p);
		// 15 rings per metre, not 26. At the higher frequency the grain beats
		// against the geometry on small parts — barrel staves and a signboard
		// both came out looking like basketwork.
		float rings = fbm(vec3(q.x * 0.7, q.y * 15.0, q.z * 2.4), 3);
		return rings * 0.78 + fbm(p * 7.0, 2) * 0.22;
	}
	if (kind == 2) {
		// Clay tile: flat within a tile, stepped between tiles.
		vec2 cell = floor(vec2(p.x, p.y) / max(unit_size, vec2(0.02)));
		return hash13(vec3(cell, 0.0)) * 0.8 + fbm(p * 14.0, 2) * 0.2;
	}
	if (kind == 3) {
		// Rubble: per-stone plus a coarse pitting.
		vec2 cell = floor(vec2(p.x + p.z, p.y) / max(unit_size, vec2(0.02)));
		return hash13(vec3(cell, 0.0)) * 0.55 + fbm(p * 7.0, 3) * 0.45;
	}
	if (kind == 4) {
		return fbm(p * 22.0, 2);
	}
	if (kind == 5) {
		return 0.5;
	}
	// Plaster: broad float marks over a fine tooth.
	return fbm(p * 1.1, 2) * 0.55 + fbm(p * 13.0, 2) * 0.45;
}

void vertex() {
	v_obj = VERTEX;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_obj * pattern_scale;
	float h = surface_height(p);

	// Value variation. Kept as a multiply on albedo rather than a mix toward
	// grey so the material's hue survives; a wall that varies in brightness
	// reads as one material lit unevenly, which is what plaster does.
	vec3 base = albedo_tint.rgb * (1.0 + (h - 0.5) * 2.0 * value_variation);

	// Grime: low on the building, and stronger on upward faces where dirt
	// actually settles. Object-space Y is the building's own height, so this
	// stays correct however the town rotates the structure.
	float low = 1.0 - clamp(v_obj.y / grime_height, 0.0, 1.0);
	float up = clamp(v_wnormal.y, 0.0, 1.0);
	float dirt = clamp(low * 0.75 + up * 0.45, 0.0, 1.0)
			* grime_amount * (0.55 + 0.45 * fbm(p * 2.6, 2));
	ALBEDO = mix(base, grime_color.rgb, dirt);

	if (kind == 5) {
		// Leaded glass: dark, smooth, and only weakly transparent — an inn's
		// windows should read as glass without showing an empty interior. The
		// low roughness is what makes it catch the sky; at 1.0 it renders as a
		// black rectangle and the whole facade reads as a ruin.
		ROUGHNESS = 0.10;
		SPECULAR = 0.85;
		METALLIC = 0.0;
		ALBEDO = mix(ALBEDO, glow_color.rgb * 0.5, clamp(window_glow, 0.0, 1.0));
		EMISSION += glow_color.rgb * window_glow;
	} else {
		ROUGHNESS = clamp(roughness_base + (h - 0.5) * 0.22, 0.05, 1.0);
		METALLIC = metallic_base;
		SPECULAR = 0.35;
	}

	// Normal perturbation from the SAME height field. Sampled by finite
	// difference in object space, projected onto the surface, then rotated
	// into view space where NORMAL lives.
	if (bump_strength > 0.001 && kind != 5) {
		float e = 0.012 * pattern_scale;
		vec3 grad = vec3(surface_height(p + vec3(e, 0.0, 0.0)) - h,
						 surface_height(p + vec3(0.0, e, 0.0)) - h,
						 surface_height(p + vec3(0.0, 0.0, e)) - h) / e;
		vec3 n = normalize(v_wnormal);
		grad -= n * dot(grad, n);
		vec3 bumped = normalize(n - grad * bump_strength * 0.06);
		NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
	}
}
