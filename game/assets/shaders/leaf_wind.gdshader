shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_prepass_alpha, diffuse_lambert_wrap;
// Individual tree leaves (Danny's fidelity decree: "real trees, lots of
// leaves"). Each leaf is a small quad; its silhouette (pointed oval + dark
// midrib) is drawn analytically from UV — no textures. UV2.x carries a
// per-leaf random phase so the canopy shimmers leaf-by-leaf instead of
// swaying as one rigid blob; a shared gust term bends whole boughs together.
// BACKLIGHT lets sun glow through the canopy like real foliage.

uniform vec4 leaf_a : source_color = vec4(0.25, 0.42, 0.18, 1.0);
uniform vec4 leaf_b : source_color = vec4(0.42, 0.58, 0.24, 1.0);
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.35;

varying vec2 v_uv;
varying float v_ph;

void vertex() {
	v_uv = UV;
	v_ph = UV2.x;
	float phase = dot(VERTEX.xz, normalize(wind_dir)) * 0.12 - TIME * wind_speed;
	float gust = sin(phase) * 0.5 + 0.5;
	gust *= gust;
	float flutter = sin(TIME * 2.6 + v_ph * 6.2831 + VERTEX.x * 0.35) * 0.045;
	VERTEX.xz += normalize(wind_dir) * (gust * 0.16) + vec2(flutter, flutter * 0.6);
	VERTEX.y += sin(TIME * 1.8 + v_ph * 6.2831) * 0.03;
}

void fragment() {
	// Pointed-oval leaf silhouette drawn from UV space.
	float t = clamp(v_uv.y, 0.0, 1.0);
	float width = pow(sin(3.1416 * t), 0.65) * 0.42;
	float a = step(abs(v_uv.x - 0.5), width);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec3 col = mix(leaf_a.rgb, leaf_b.rgb, v_ph);
	col *= mix(0.8, 1.1, t);                               // tip catches light
	col *= 1.0 - 0.18 * step(abs(v_uv.x - 0.5), 0.025);   // midrib line
	ALBEDO = pow(col, vec3(2.2));
	BACKLIGHT = ALBEDO * 0.55;
	ROUGHNESS = 0.85;
}
