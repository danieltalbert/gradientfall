// Night-sky stars for CelestialLayer's dome.
//
// Draws each MultiMesh quad as a camera-facing point of light: a hot core,
// a soft halo, and a faint four-point diffraction cross. Additive and
// unshaded so stars only ever brighten the sky, never occlude it;
// depth_draw_never keeps them from writing depth over one another.
//
// Driven by celestial_layer.gd, which fades `visibility` in at dusk and out
// at dawn, and writes a per-star random value into INSTANCE_CUSTOM.x —
// that seed sets both the twinkle rate/offset and the star's color, so
// every star behaves independently from one shared material.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 0 = invisible (day), 1 = full night. Animated by CelestialLayer.
uniform float visibility : hint_range(0.0, 1.0) = 0.0;
// Endpoints of the stellar color range; each star picks a point between
// them from its seed.
uniform vec4 cool_color : source_color = vec4(0.60, 0.76, 1.0, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.82, 0.48, 1.0);

// Per-instance random seed, forwarded from INSTANCE_CUSTOM.x.
varying float v_seed;

// Billboard the quad by replacing the model basis with the camera's, while
// preserving the instance's own X/Y scale so per-star sizes survive. The Z
// axis is taken unscaled — the quad is flat, so its depth extent is unused.
void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mat4 billboard_model = MODEL_MATRIX;
	billboard_model[0].xyz = INV_VIEW_MATRIX[0].xyz * sx;
	billboard_model[1].xyz = INV_VIEW_MATRIX[1].xyz * sy;
	billboard_model[2].xyz = INV_VIEW_MATRIX[2].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard_model;
	v_seed = INSTANCE_CUSTOM.x;
}

void fragment() {
	// Radial distance from the quad's center, in UV units (0.5 = edge).
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	// Three stacked falloffs: a tight core, a wide halo, and a diffraction
	// cross built from two perpendicular exponential streaks (sharp across
	// the streak, slow along it).
	float core = 1.0 - smoothstep(0.018, 0.095, d);
	float halo = 1.0 - smoothstep(0.04, 0.46, d);
	float cross = exp(-abs(p.x) * 34.0) * exp(-abs(p.y) * 5.0)
			+ exp(-abs(p.y) * 34.0) * exp(-abs(p.x) * 5.0);
	// Brightness pulse in [0.72, 1.0]. Both the rate and the phase come
	// from the seed, so no two stars twinkle together.
	float twinkle = 0.72 + 0.28 * sin(TIME * (0.8 + v_seed * 2.1) + v_seed * 41.0);
	vec3 col = mix(cool_color.rgb, warm_color.rgb, fract(v_seed * 7.31));
	ALBEDO = col;
	EMISSION = col * (1.65 + core * 3.2);
	ALPHA = clamp((core + halo * 0.42 + cross * 0.18) * twinkle * visibility, 0.0, 1.0);
}
