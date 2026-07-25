shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
// Taller meadow accents. The shared mesh is built from five curved ribbons;
// this material adds two-scale travelling wind, individual blade flutter,
// root occlusion, and gentle back-lighting without turning the field neon.
//
// Used on the taller tufted grass MultiMesh in meadow_flora.gd — the
// short infinite ground cover uses grass_field.gdshader instead. Distant
// blades scale to nothing and then discard, which is this shader's LOD:
// there is no mesh swap, the geometry simply shrinks out of existence
// between 148 m and 218 m. Channel contract: UV.y is 0 at root and 1 at
// tip, UV2.x is a per-blade random phase, and instance COLOR carries the
// blade tint (see the sRGB note in vertex()).

uniform vec2 wind_dir = vec2(0.75, 0.55);
// Maximum lean (in model units) at full gust, and the gust travel rate.
uniform float sway_strength : hint_range(0.0, 0.7) = 0.21;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.05;

varying float v_tip;
varying float v_gust;
varying float v_visibility;
varying vec3 v_col;

// Bend each blade under the travelling gust, hinged at the root, then apply
// distance fade.
void vertex() {
	v_tip = UV.y;
	// MultiMesh colors are authored as display values rather than source_color
	// uniforms, so they need explicit conversion to the renderer's linear space.
	v_col = pow(COLOR.rgb, vec3(2.2));
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Wind is world-space while VERTEX is local, so project the direction
	// onto the instance's axes — each blade is randomly yawed.
	vec3 world_direction = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	vec2 local_direction = normalize(vec2(
		dot(world_direction, model_x), dot(world_direction, model_z)
	));
	vec2 local_cross = vec2(-local_direction.y, local_direction.x);

	// Two perpendicular travelling waves at different rates, so the gust
	// front sweeping the meadow never visibly repeats.
	float march = dot(world_position.xz, normalize(wind_dir)) * 0.055 - TIME * sway_speed;
	float crossing = dot(world_position.xz, vec2(-wind_dir.y, wind_dir.x)) * 0.024 + TIME * 0.29;
	float wave = sin(march) * 0.7 + sin(crossing) * 0.3;
	// Squaring biases toward calm — gusts arrive in pushes, with lulls.
	v_gust = smoothstep(-0.58, 0.76, wave);
	v_gust *= v_gust;
	// Displacement rises faster than linearly toward the tip, so the blade
	// curves like a hinged stalk instead of shearing as a rigid strip.
	float tip_weight = pow(v_tip, 1.55);
	float flutter = sin(TIME * 3.6 + UV2.x * 6.2831853 + world_position.x * 0.17 + world_position.z * 0.11);
	// Constant 0.025 lean keeps the field alive even at zero gust.
	VERTEX.xz += local_direction * ((0.025 + v_gust * sway_strength) * tip_weight);
	VERTEX.xz += local_cross * (flutter * 0.018 * tip_weight);
	// Dip as it bends: a leaning blade is shorter than an upright one.
	VERTEX.y -= v_gust * 0.035 * tip_weight;
	// Tilt normals 40% toward straight up. True ribbon normals make a field
	// read as harshly lit facets; biasing skyward gives the soft, uniform
	// meadow lighting the look-dev calls for.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.4));

	// Distance LOD: blades shrink to nothing between 148 m and 218 m and the
	// fragment stage discards them. Scaling VERTEX shrinks each blade toward
	// its own origin, so tufts sink away rather than popping out.
	float camera_distance = distance(world_position, CAMERA_POSITION_WORLD);
	v_visibility = 1.0 - smoothstep(148.0, 218.0, camera_distance);
	VERTEX *= v_visibility;
}

// Shade the blade root-to-tip. Darker at the root fakes the occlusion of a
// dense sward; back-lighting gives the translucency of a lit blade.
void fragment() {
	// Fully shrunk blades cost nothing to skip entirely.
	if (v_visibility < 0.015) {
		discard;
	}
	ALBEDO = v_col * mix(0.82, 1.06, smoothstep(0.0, 0.88, v_tip));
	ALBEDO *= 1.0 + v_gust * v_tip * 0.025;
	// More self-emission at the root than the tip, lifting the shadowed
	// base out of pure black without brightening the whole field.
	EMISSION = v_col * mix(0.09, 0.05, v_tip);
	BACKLIGHT = v_col * (0.26 + v_tip * 0.18);
	ROUGHNESS = 0.95;
	SPECULAR = 0.075;
	RIM = 0.07 * smoothstep(0.28, 1.0, v_tip);
	RIM_TINT = 0.28;
}
