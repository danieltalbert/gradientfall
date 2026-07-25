shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Analytic bark shared by trunk, root flare, boughs, and twigs. Several noise
// scales break the vertical ridges into plates, hairline cracks, and quiet moss
// staining. Tall, radial branch vertices follow the same wind front as leaves
// while the roots stay planted.
//
// Applied to the tree trunks meadow_flora.gd builds. Unlike the horizon
// trees (which use the flat toon shader), meadow trees are close enough to
// need real surface detail, so this is a lit material with procedural bark
// — no textures. It shares wind_dir and wind_speed with leaf_wind.gdshader
// so trunk sway and leaf motion ride the same gust front. Positions are in
// meters; UV.x wraps once around the trunk's circumference.

uniform vec4 bark_color : source_color = vec4(0.42, 0.3, 0.19, 1.0);
// Highlight on ridge crests and the dark tone in grooves and cracks.
uniform vec4 bark_light : source_color = vec4(0.57, 0.42, 0.25, 1.0);
uniform vec4 groove_color : source_color = vec4(0.24, 0.15, 0.085, 1.0);
uniform vec4 moss_color : source_color = vec4(0.2, 0.31, 0.11, 1.0);
// Horizontal wind direction (world XZ) and gust rate. Match these to the
// leaf shader on the same tree or the canopy will sway out of step.
uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.05;
// Full height (m) of this tree, used to normalize sway by altitude.
uniform float tree_height = 9.0;

varying vec2 v_uv;
varying vec3 v_world_position;
varying vec3 v_local_position;

// Cheap hash -> pseudo-random float in [0, 1) from a 2D lattice coordinate.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise: bilinear blend of four hashed corners with a smoothstep
// ease, so the lattice never shows as a grid.
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

// Wind sway. The gust is a wave travelling across the meadow, so trees bend
// in sequence rather than all at once, and each vertex's response scales
// with how high and how far out on a branch it sits — the trunk base stays
// planted while twig tips move most.
void vertex() {
	v_uv = UV;
	vec3 initial_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The wind is defined in world space, but VERTEX is local, so the
	// direction is projected onto the model's axes before being applied.
	// Without this, rotated tree instances would bend the wrong way.
	vec3 world_direction = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	vec2 local_direction = normalize(vec2(
		dot(world_direction, model_x), dot(world_direction, model_z)
	));
	// Position along the gust front: the world-space term makes the wave
	// travel, the TIME term moves it downwind.
	float march = dot(initial_world.xz, normalize(wind_dir)) * 0.045 - TIME * wind_speed;
	// Squaring biases the gust toward calm, so wind arrives in pushes with
	// lulls between rather than a constant sine.
	float gust = smoothstep(-0.62, 0.8, sin(march));
	gust *= gust;
	// No sway below ~28% of tree height; full sway above ~92%.
	float height_weight = smoothstep(0.28, 0.92, clamp(VERTEX.y / tree_height, 0.0, 1.0));
	// Distance (m) from the trunk axis: boughs and twigs flex, the bole does not.
	float branch_weight = smoothstep(0.32, 1.5, length(VERTEX.xz));
	VERTEX.xz += local_direction * gust * 0.07 * height_weight * branch_weight;
	v_local_position = VERTEX;
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Build the bark surface in layers: vertical ridges, then plate cracks,
// then broad tonal drift, then moss near the ground.
void fragment() {
	// UV.x wraps the trunk once, so scaling it by 2*pi gives an angle —
	// ridges built on it therefore meet seamlessly around the back.
	float circumference = v_uv.x * 6.2831853;
	// Phase wander bends the ridges as they rise; without it they would be
	// perfectly straight vertical stripes.
	float wander = vnoise(vec2(v_uv.x * 7.0, v_world_position.y * 0.42)) * 3.2;
	// 8 broad ridges around the trunk, contrast-pushed into distinct bands.
	float broad_ridge = sin(circumference * 8.0 + wander) * 0.5 + 0.5;
	broad_ridge = smoothstep(0.18, 0.82, broad_ridge);
	// 21 finer ridges, drifting with height for a subtle spiral.
	float fine_ridge = sin(circumference * 21.0 + v_world_position.y * 0.24 + wander) * 0.5 + 0.5;
	// High smoothstep thresholds turn noise into sparse cracks rather than
	// general mottling: only the top few percent of values register.
	float plates = vnoise(vec2(v_uv.x * 23.0, v_world_position.y * 2.6));
	float horizontal_crack = smoothstep(0.87, 0.965, plates);
	float vertical_crack = smoothstep(0.91, 0.985, vnoise(vec2(v_uv.x * 58.0, v_world_position.y * 0.72)));

	vec3 color = mix(groove_color.rgb, bark_color.rgb, broad_ridge);
	color = mix(color, bark_light.rgb, fine_ridge * 0.22);
	color = mix(color, groove_color.rgb, horizontal_crack * 0.72 + vertical_crack * 0.4);
	float tonal_drift = vnoise(v_world_position.xz * 0.43 + v_world_position.y * 0.08);
	color *= 0.86 + tonal_drift * 0.24;
	// Moss fades out between 1.2 m and 4.8 m up the trunk. This uses LOCAL
	// height, not world, so trees on a hillside all grow moss from their own
	// base rather than from a shared world altitude.
	float low_trunk = 1.0 - smoothstep(1.2, 4.8, max(v_local_position.y, 0.0));
	// Sampled in world XZ so neighboring trees in a damp hollow agree.
	float moss = smoothstep(0.58, 0.84, vnoise(v_world_position.xz * 0.68 + vec2(9.0, -13.0)));
	color = mix(color, moss_color.rgb, moss * low_trunk * 0.24);
	ALBEDO = color;
	// A whisper of self-emission keeps trunks from going pitch black at
	// night, when the moon light alone leaves them unreadable.
	EMISSION = color * 0.035;
	// Cracks are fully rough; intact bark keeps a trace of sheen.
	ROUGHNESS = mix(0.82, 1.0, horizontal_crack);
	SPECULAR = 0.1;
	RIM = 0.08;
	RIM_TINT = 0.28;
}
