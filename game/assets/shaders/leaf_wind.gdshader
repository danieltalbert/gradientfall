shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert_wrap, specular_schlick_ggx;
// Individually modelled broadleaf cards. UV draws a tapered, subtly serrated
// silhouette with a midrib and side veins; UV2 carries per-leaf phase and crown
// height. A world-space gust drives the whole crown while high-frequency
// flutter remains unique to each leaf.
//
// Applied to the leaf cards meadow_flora.gd builds for each meadow tree
// (about a thousand per tree), paired with bark.gdshader on the same trunk —
// keep wind_dir and wind_speed identical between the two or the canopy will
// sway out of step with its own branches. The silhouette is cut in the
// fragment stage with alpha scissor rather than a texture, so leaf shape
// costs no memory. Vertex channel contract: UV is the leaf card's own 0-1
// space (y runs stem to tip), UV2.x is a per-leaf random phase, UV2.y is
// normalized height in the crown.

uniform vec4 leaf_a : source_color = vec4(0.28, 0.46, 0.13, 1.0);
// Two base greens mixed per leaf by phase, plus a lighter tone blended into
// the crown top where new growth catches the most light.
uniform vec4 leaf_b : source_color = vec4(0.42, 0.58, 0.18, 1.0);
uniform vec4 young_leaf : source_color = vec4(0.54, 0.66, 0.22, 1.0);
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.05;
// Declared for parity with bark.gdshader's uniform set; crown height comes
// from UV2.y here, so this value is not read by this shader.
uniform float tree_height = 9.0;

varying vec2 v_uv;
varying float v_phase;
varying float v_height;
varying float v_gust;

// Two-scale motion: a slow travelling gust that moves the whole crown in
// step with neighboring trees, plus fast per-leaf flutter that keeps
// individual cards alive. Both scale by crown height, so inner leaves near
// the trunk stay comparatively still.
void vertex() {
	v_uv = UV;
	v_phase = UV2.x;
	v_height = UV2.y;
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Wind is world-space but VERTEX is local, so the direction is projected
	// onto the model's axes — otherwise rotated trees would bend wrongly.
	vec3 world_direction = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	vec2 local_direction = normalize(vec2(
		dot(world_direction, model_x), dot(world_direction, model_z)
	));
	vec2 local_cross = vec2(-local_direction.y, local_direction.x);

	// Two perpendicular travelling waves — one downwind, one across it, at a
	// different rate — so the gust pattern never repeats visibly across the
	// meadow the way a single sine would.
	float march = dot(world_position.xz, normalize(wind_dir)) * 0.045 - TIME * wind_speed;
	float crossing = dot(world_position.xz, vec2(-wind_dir.y, wind_dir.x)) * 0.021 + TIME * 0.27;
	float wave = sin(march) * 0.72 + sin(crossing) * 0.28;
	// Squaring biases toward calm: wind arrives in pushes with lulls between.
	v_gust = smoothstep(-0.62, 0.78, wave);
	v_gust *= v_gust;
	float crown_weight = smoothstep(0.18, 0.9, v_height);
	// Two incommensurate flutter rates keyed to the per-leaf phase, so no two
	// leaves shiver together and the pattern never loops.
	float flutter = sin(TIME * 4.1 + v_phase * 6.2831853 + world_position.y * 0.7);
	float flutter_2 = sin(TIME * 6.7 + v_phase * 11.7 + world_position.x * 0.31);
	// Bend downwind, shiver across the wind, and lift slightly — the vertical
	// term is what keeps a gust from looking like a flat horizontal shove.
	VERTEX.xz += local_direction * (v_gust * 0.13 * crown_weight);
	VERTEX.xz += local_cross * ((flutter * 0.035 + flutter_2 * 0.014) * crown_weight);
	VERTEX.y += (flutter * 0.018 + v_gust * 0.025) * crown_weight;
}

// Cut the leaf silhouette out of its quad and shade it. Everything is
// analytic — no leaf texture exists anywhere in the project.
void fragment() {
	// t runs 0 at the stem to 1 at the tip; centered_x is distance from the
	// midrib.
	float t = clamp(v_uv.y, 0.0, 1.0);
	float centered_x = abs(v_uv.x - 0.5);
	// sin(pi*t) is the tapered outline — zero at both ends, widest in the
	// middle. The 0.62 power flattens that arc so the leaf is broad along
	// its length rather than a pointed ellipse.
	float base_width = pow(max(sin(3.14159265 * t), 0.0), 0.62) * 0.465;
	// Fine tooth ripple on the edge, faded out at stem and tip by the same
	// sin(pi*t) envelope so the serration doesn't fray the ends.
	float serration = sin(t * 62.0 + v_phase * 9.0) * 0.018 * sin(3.14159265 * t);
	// A slow lean that makes each half of the blade a different width, so
	// leaves aren't perfectly mirror-symmetric.
	float asymmetry = (v_uv.x - 0.5) * sin(t * 9.0 + v_phase * 6.0) * 0.025;
	// Hard in/out test, resolved by alpha scissor — no soft edge, which is
	// what keeps a thousand overlapping leaf cards sorting correctly.
	float silhouette = step(centered_x, base_width + serration + asymmetry);
	ALPHA = silhouette;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec3 color = mix(leaf_a.rgb, leaf_b.rgb, v_phase);
	color = mix(color, young_leaf.rgb, smoothstep(0.68, 1.0, v_height) * 0.18);
	color *= mix(0.84, 1.08, t);
	// Veins as darkening rather than geometry: a narrow midrib down the
	// center, and side veins from a high power of a sine, which compresses
	// the wave into thin lines with wide flat gaps between.
	float midrib = 1.0 - smoothstep(0.008, 0.032, centered_x);
	float side_veins = pow(abs(sin(t * 34.0 + centered_x * 18.0)), 18.0);
	color *= 1.0 - midrib * 0.15 - side_veins * 0.045;
	// Leaves catch a touch more light as they turn into the gust.
	color *= 1.0 + v_gust * 0.035;
	ALBEDO = color;
	// Slight self-emission so foliage stays readable under moonlight.
	EMISSION = color * 0.045;
	// Translucency: leaves glow when backlit, more so toward the thinner tip.
	BACKLIGHT = color * (0.3 + 0.18 * t);
	ROUGHNESS = 0.88;
	SPECULAR = 0.11;
	RIM = 0.08;
	RIM_TINT = 0.3;
}
