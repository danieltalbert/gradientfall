// The moon disc for CelestialLayer's night sky.
//
// A single camera-facing quad painted as a cratered disc with a soft outer
// halo. Additive and unshaded — it is a light source in the sky, not lit
// geometry — with depth writes off so cloud banks in front still composite
// correctly. Craters are procedural value noise; no textures are used
// anywhere in this project.
//
// celestial_layer.gd owns `visibility`, ramping it in after the first stars
// appear and out again at dawn. Note that the visual moon and SkyCycle's
// MoonLight are independent: this shader does not track that light's angle.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 0 = hidden (day), 1 = fully visible. Animated by CelestialLayer.
uniform float visibility : hint_range(0.0, 1.0) = 0.0;
// Base tint of the lunar surface, before crater and limb shading.
uniform vec4 moon_color : source_color = vec4(0.76, 0.84, 1.0, 1.0);

varying vec2 v_uv;

// Cheap hash -> pseudo-random float in [0, 1) from a 2D cell coordinate.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise: bilinear blend of four hashed lattice corners, with the
// smoothstep curve f*f*(3-2f) easing the interpolation so cell boundaries
// don't show as a grid.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

// Billboard the quad toward the camera, preserving the instance's X/Y
// scale so the authored disc size is unchanged.
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
	// The disc fills most of the quad with a 0.035-wide antialiased edge;
	// the halo bleeds well past it for atmospheric glow.
	float disc = 1.0 - smoothstep(0.46, 0.495, d);
	float halo = 1.0 - smoothstep(0.30, 0.74, d);
	// Two noise octaves: broad maria plus finer cratering.
	float craters = noise(v_uv * 15.0) * 0.65 + noise(v_uv * 43.0) * 0.35;
	// Fake sphere shading: sqrt(1 - r²) is the z of a unit hemisphere, so
	// brightness falls off toward the rim. The 3.9 factor makes it reach
	// zero right at the disc edge (r ≈ 0.5) instead of at r = 1.
	float limb = sqrt(max(0.0, 1.0 - d * d * 3.9));
	vec3 surface = moon_color.rgb * (0.72 + craters * 0.22) * (0.72 + limb * 0.28);
	ALBEDO = surface;
	EMISSION = surface * (1.6 + disc * 0.65);
	ALPHA = clamp((disc + halo * 0.20) * visibility, 0.0, 1.0);
}
