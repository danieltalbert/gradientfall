shader_type spatial;
// Procedural bark (Danny's fidelity decree: "lines in the wood like a real
// tree"). Vertical ridge-and-groove striping wanders with noise so no two
// stretches repeat, with fine horizontal cracking — all analytic, no
// textures. UV.x wraps the trunk circumference, world Y runs up it.

uniform vec4 bark_color : source_color = vec4(0.36, 0.27, 0.2, 1.0);
uniform vec4 groove_color : source_color = vec4(0.2, 0.14, 0.1, 1.0);

varying vec2 v_uv;
varying vec3 v_wpos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_uv = UV;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Wandering vertical ridges.
	float wander = vnoise(vec2(v_uv.x * 6.0, v_wpos.y * 0.5)) * 2.6;
	float ridge = sin(v_uv.x * 62.83 + wander) * 0.5 + 0.5;
	ridge = smoothstep(0.25, 0.75, ridge);
	// Fine horizontal cracks breaking the ridges.
	float crack = smoothstep(0.75, 0.95, vnoise(vec2(v_uv.x * 30.0, v_wpos.y * 4.0)));
	vec3 col = mix(groove_color.rgb, bark_color.rgb, ridge);
	col = mix(col, groove_color.rgb, crack * 0.6);
	col *= 0.92 + 0.16 * vnoise(v_wpos.xy * 0.8);  // large-scale tonal drift
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 1.0;
}
