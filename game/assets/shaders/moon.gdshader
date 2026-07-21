shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Billboard moon with a REAL lunar phase: the disc is shaded as a sphere lit
// by the actual sun direction, so the terminator sweeps correctly as the sun
// travels — full when opposite the sun, a crescent when trailing it.
uniform float visibility : hint_range(0.0, 1.0) = 0.0;
uniform vec4 moon_color : source_color = vec4(0.82, 0.87, 1.0, 1.0);
uniform vec3 sun_dir_world = vec3(0.35, 0.72, 0.28);

varying vec2 v_uv;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mat4 billboard_model = MODEL_MATRIX;
	billboard_model[0].xyz = INV_VIEW_MATRIX[0].xyz * sx;
	billboard_model[1].xyz = INV_VIEW_MATRIX[1].xyz * sy;
	billboard_model[2].xyz = INV_VIEW_MATRIX[2].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard_model;
	v_uv = UV;
}

void fragment() {
	vec2 p = v_uv - vec2(0.5);
	float d = length(p);
	float disc = 1.0 - smoothstep(0.44, 0.468, d);

	// Treat the billboard as the visible hemisphere of a sphere: reconstruct a
	// view-space normal from the disc, take it to world space, and light it
	// with the true sun direction. This IS the lunar phase.
	vec2 q = p / 0.45;
	float rr = clamp(dot(q, q), 0.0, 1.0);
	vec3 n_view = normalize(vec3(q.x, -q.y, sqrt(max(1.0 - rr, 0.0002))));
	vec3 n_world = normalize(mat3(INV_VIEW_MATRIX) * n_view);
	float terminator = dot(n_world, normalize(sun_dir_world));
	float lit = smoothstep(-0.02, 0.22, terminator);
	// The night side keeps a whisper of earthshine so the full circle reads.
	float light_amount = mix(0.045, 1.0, lit);

	// Maria + craters: two noise octaves, darker "seas" in the low band.
	float relief = noise(v_uv * 14.0) * 0.6 + noise(v_uv * 41.0) * 0.4;
	float maria = smoothstep(0.36, 0.62, noise(v_uv * 5.0 + vec2(3.7, 1.2)));
	float surface_tone = (0.78 + relief * 0.22) * mix(1.0, 0.68, maria);
	float limb = sqrt(max(0.0, 1.0 - rr * 0.92));  // limb darkening
	vec3 surface = moon_color.rgb * surface_tone * (0.70 + limb * 0.30) * light_amount;

	// Halo follows the lit fraction so a thin crescent doesn't over-glow.
	float lit_center = clamp(dot(normalize(mat3(INV_VIEW_MATRIX) * vec3(0.0, 0.0, 1.0)),
			normalize(sun_dir_world)) * 0.5 + 0.5, 0.05, 1.0);
	float halo = (1.0 - smoothstep(0.30, 0.78, d)) * (1.0 - disc) * lit_center;

	ALBEDO = surface + moon_color.rgb * halo * 0.55;
	EMISSION = surface * (1.35 + disc * 0.55) + moon_color.rgb * halo * 0.85;
	ALPHA = clamp((disc + halo * 0.30) * visibility, 0.0, 1.0);
}
