shader_type spatial;
render_mode specular_schlick_ggx;
// Kern's eyes — fully analytic. The eyeball mesh is UV'd polar around the
// pupil axis: UV.y = angular distance from the pupil centre (0 at the pupil,
// 1 at the back pole), UV.x = angle around that axis. From those two numbers
// we draw: pupil, iris with radial fibre striations and a darker limbal ring,
// a collarette (the brighter inner ring real irises have), the sclera with a
// warm tint and faint corner veins, and a wet specular glint. The life of an
// eye is 90% that glint, so the light() pass is sharp and generous.

group_uniforms iris;
uniform vec4 iris_color : source_color = vec4(0.30, 0.47, 0.28, 1.0);
uniform vec4 iris_edge_color : source_color = vec4(0.10, 0.20, 0.12, 1.0);
uniform vec4 collarette_color : source_color = vec4(0.58, 0.52, 0.24, 1.0);
uniform float iris_radius : hint_range(0.02, 0.4) = 0.155;
uniform float pupil_radius : hint_range(0.01, 0.2) = 0.055;
uniform float fiber_strength : hint_range(0.0, 1.0) = 0.5;

group_uniforms sclera;
uniform vec4 sclera_color : source_color = vec4(0.93, 0.90, 0.85, 1.0);
uniform vec4 vein_color : source_color = vec4(0.72, 0.36, 0.30, 1.0);
uniform float vein_amount : hint_range(0.0, 1.0) = 0.22;

group_uniforms shading;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.68, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.10;
// The upper lid throws a soft occlusion shadow across the top of the eye.
uniform float lid_shadow : hint_range(0.0, 1.0) = 0.45;

varying vec2 v_uv;

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
	v_uv = UV;
}

void fragment() {
	float r = v_uv.y;           // 0 at pupil centre -> 1 at back pole
	float ang = v_uv.x * 6.2831853;

	// --- Iris ---
	float fibers = vnoise(vec2(v_uv.x * 60.0, r * 26.0)) * 0.6
			+ vnoise(vec2(v_uv.x * 140.0, r * 8.0)) * 0.4;
	float radial = clamp(r / max(iris_radius, 0.001), 0.0, 1.0);
	vec3 iris = mix(iris_color.rgb, iris_edge_color.rgb,
			smoothstep(0.45, 1.0, radial));
	// Collarette: brighter flecked ring around the pupil.
	iris = mix(iris, collarette_color.rgb,
			smoothstep(0.30, 0.16, radial) * smoothstep(0.06, 0.20, radial) * 0.7);
	iris *= 1.0 + (fibers - 0.5) * 2.0 * fiber_strength;
	// Limbal ring: the dark rim that makes an iris read as alive.
	iris = mix(iris, iris_edge_color.rgb * 0.45,
			smoothstep(iris_radius * 0.80, iris_radius, r) * 0.9);

	// --- Pupil (soft edged, slightly breathing with noise) ---
	float pupil = 1.0 - smoothstep(pupil_radius * 0.85, pupil_radius * 1.15, r);
	iris = mix(iris, vec3(0.012, 0.012, 0.016), pupil);

	// --- Sclera with corner veins (denser away from the iris) ---
	vec3 sclera = sclera_color.rgb;
	float vein_field = vnoise(vec2(v_uv.x * 34.0, r * 10.0));
	float veins = smoothstep(0.68, 0.92, vein_field)
			* smoothstep(iris_radius * 1.4, 0.85, r) * vein_amount;
	sclera = mix(sclera, vein_color.rgb, veins);
	// Gentle occlusion darkening toward the back / corners of the ball.
	sclera *= 1.0 - smoothstep(0.35, 0.9, r) * 0.35;

	vec3 col = mix(iris, sclera, smoothstep(iris_radius, iris_radius * 1.06, r));

	// Upper-lid contact shadow: darker toward "up" in object space.
	float up_shade = clamp(sin(ang) * 0.5 + 0.5, 0.0, 1.0);  // 1 toward top
	col *= 1.0 - lid_shadow * up_shade * smoothstep(0.5, 0.05, r);

	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	EMISSION += shadow_fill.rgb * fill_amount * ALBEDO;
}

void light() {
	float ndl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float lit = smoothstep(0.0, 0.25, ndl * ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * mix(0.45, 1.0, lit);
	// The wet glint: one tight hot dot plus a broad soft sheen.
	vec3 h = normalize(normalize(VIEW) + normalize(LIGHT));
	float ndh = clamp(dot(normalize(NORMAL), h), 0.0, 1.0);
	SPECULAR_LIGHT += LIGHT_COLOR * (pow(ndh, 420.0) * 2.6 + pow(ndh, 40.0) * 0.18)
			* ATTENUATION;
}
