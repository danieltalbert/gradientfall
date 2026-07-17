shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;
// Wind-blown meadow grass (GDD §10 non-negotiable: living ground cover).
// Blades are solid low-poly triangles — no textures, per the generated-in-
// code rule. UV.y is 0 at the root, 1 at the tip: it drives both the sway
// weight (roots planted, tips dancing) and the root→tip color gradient.
// Per-instance COLOR carries hue variation so the field never bands.

uniform float sway_strength : hint_range(0.0, 1.0) = 0.22;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.7;

varying float v_tip;
varying vec3 v_col;

void vertex() {
	v_tip = UV.y;
	// Instance colors are authored as display (sRGB) values; linearize so
	// the field renders at the intended saturation instead of washing out.
	v_col = pow(COLOR.rgb, vec3(2.2));
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Two sine bands at different scales read as gusts moving through the
	// field rather than the whole meadow metronoming in unison.
	float phase = wpos.x * 0.35 + wpos.z * 0.27;
	float gust = sin(TIME * sway_speed + phase)
			+ 0.45 * sin(TIME * sway_speed * 2.33 + phase * 1.71);
	VERTEX.x += gust * sway_strength * v_tip;
	VERTEX.z += gust * sway_strength * 0.55 * v_tip;
	// Blades collapse to a zero-area point past ~100 m: distant hills keep
	// their clean baked color (no tip speckle, no flattened-splat carpet)
	// and the GPU skips the overdraw. Scaling ALL axes matters — y alone
	// leaves bright triangle splats lying on far slopes.
	float cam_dist = distance(wpos, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(85.0, 125.0, cam_dist);
}

void fragment() {
	// Roots sit near the terrain's own green so blades read as part of the
	// ground, not sticks standing on it; tips carry the instance hue.
	vec3 root = v_col * 0.62;
	ALBEDO = mix(root, v_col * 1.05, v_tip);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
