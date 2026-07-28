shader_type spatial;
// Kern's iris — drawn on the flat cornea disc (a CylinderMesh cap; its local
// XZ plane is the disc face, so radial coords come straight from VERTEX.xz).
// A radial gradient (warm centre -> deep limbal ring), fine fibre striations,
// and — the mystical part — a faint gradient-hue shimmer and an inner glow that
// swell with `awaken`, so at rest his eyes look human and, as the First Model
// surfaces, they take on a quiet inner light. Pupil + catchlight are separate
// meshes stacked in front, so this only paints the coloured ring.

uniform float iris_radius : hint_range(0.001, 0.05) = 0.0084;
uniform vec4 iris_color : source_color = vec4(0.20, 0.33, 0.20, 1.0);
uniform vec4 iris_inner : source_color = vec4(0.34, 0.50, 0.30, 1.0);
uniform vec4 iris_edge : source_color = vec4(0.06, 0.12, 0.09, 1.0);
uniform float fiber_strength : hint_range(0.0, 1.0) = 0.28;
uniform float awaken : hint_range(0.0, 1.0) = 0.12;
uniform vec4 glow_color : source_color = vec4(0.5, 0.9, 1.0, 1.0);

varying vec3 v_lp;

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

vec3 hue(float h) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return k;
}

void vertex() {
	v_lp = VERTEX;
}

void fragment() {
	vec2 p = v_lp.xz / iris_radius;   // -1..1 across the disc
	float r = clamp(length(p), 0.0, 1.0);
	float ang = atan(p.y, p.x);

	// Radial iris gradient with a dark limbal ring.
	vec3 col = mix(iris_inner.rgb, iris_color.rgb, smoothstep(0.12, 0.78, r));
	col = mix(col, iris_edge.rgb, smoothstep(0.80, 1.0, r));

	// Fibre striations radiating from the pupil.
	float fib = vnoise(vec2(ang * 9.0, r * 6.0)) * 0.6
			+ vnoise(vec2(ang * 22.0, r * 3.0)) * 0.4;
	col *= 1.0 + (fib - 0.5) * 2.0 * fiber_strength;

	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.22;
	SPECULAR = 0.5;

	float lvl = clamp(awaken, 0.0, 1.0);
	// Inner glow: the iris lights from within as Kern awakens.
	EMISSION += pow(col, vec3(2.2)) * (0.04 + lvl * 0.9) * smoothstep(1.0, 0.25, r);
	// Gradient-hue shimmer sweeping around the iris — subtle at rest, a slow
	// aurora when charged.
	float h = fract(ang / 6.2831853 + TIME * 0.06 + r * 0.3);
	EMISSION += hue(h) * glow_color.rgb * (0.02 + lvl * 0.12) * smoothstep(0.95, 0.35, r);
}
