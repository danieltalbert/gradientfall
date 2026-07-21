shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_back;

// Climbable Gradient Peaks surface — a material the player stands on, so it
// must hold up at arm's length, not just on the horizon. The mesh bakes a
// slope/altitude-chosen base color (soil, rock, scree, alpine turf, snow) into
// vertex color; this shader adds close-range rock-plate mottle, broken
// sediment strata, cross-cut fractures, talus grain, and crisp wind-broken
// snow, then lights it with the same wrapped-diffuse + rim + sky-fill recipe
// the rest of the world uses so it reads as one place with the meadow.
//
// Geometry hands the shader two authored channels:
//   UV.x = flatness   (1 on walkable shelves / soil benches, 0 on cliffs)
//   UV.y = altitude    (0 at the meadow seam, 1 at the highest summit)

group_uniforms rock;
uniform float detail_scale : hint_range(0.005, 0.2) = 0.05;
uniform float rock_detail : hint_range(0.0, 0.6) = 0.32;
uniform float strata_strength : hint_range(0.0, 0.6) = 0.26;
uniform float fracture_strength : hint_range(0.0, 0.6) = 0.24;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.85;
uniform float seed_offset = 0.0;

group_uniforms ground;
uniform float dirt_grain : hint_range(0.0, 0.6) = 0.28;
uniform float scree_strength : hint_range(0.0, 0.6) = 0.3;
uniform vec4 grass_tint : source_color = vec4(0.315, 0.44, 0.165, 1.0);
uniform float grass_blend : hint_range(0.0, 1.0) = 0.6;

group_uniforms snow;
uniform vec4 snow_tint : source_color = vec4(0.78, 0.845, 0.93, 1.0);
uniform vec4 snow_shadow_tint : source_color = vec4(0.68, 0.75, 0.87, 1.0);
uniform float snowline : hint_range(0.0, 1.0) = 0.6;
uniform float snow_softness : hint_range(0.01, 0.3) = 0.11;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.85;

group_uniforms atmosphere;
uniform vec4 haze_tint : source_color = vec4(0.55, 0.66, 0.78, 1.0);
uniform float haze_amount : hint_range(0.0, 0.5) = 0.05;
uniform vec4 shadow_fill : source_color = vec4(0.34, 0.45, 0.6, 1.0);
uniform float fill_amount : hint_range(0.0, 0.25) = 0.075;

varying vec3 v_world_position;
varying vec3 v_world_normal;
varying vec3 v_base_color;
varying float v_flatness;
varying float v_altitude;


float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0));
	float low = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
	float high = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
	return mix(low, high, f.z);
}


float fbm(vec3 p) {
	float result = 0.0;
	float weight = 0.56;
	for (int octave = 0; octave < 4; octave++) {
		result += value_noise(p) * weight;
		p = p * 2.07 + vec3(7.1, 3.7, 11.9);
		weight *= 0.5;
	}
	return result / 1.05;
}


void vertex() {
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	// Procedural meshes author display-space colors; linearize like the terrain.
	v_base_color = pow(COLOR.rgb, vec3(2.2));
	v_flatness = UV.x;
	v_altitude = UV.y;
}


// Meso-scale surface relief the geometry grid is too coarse to carry: rock
// plates, fist-size rubble, terraced ledge steps on the cliffs, and soft
// wind-carved dunes where snow covers everything. Sampled three times per
// fragment to derive a bumped normal, so it stays two-octave cheap.
float surface_relief(vec3 p, float snow_w, float cliff, float near_w, vec3 seed) {
	// Creased plates, stretched tall: water drains DOWN a mountain face, so the
	// crease field runs vertical — couloir streaks instead of isotropic stucco.
	vec3 q = p * vec3(0.28, 0.09, 0.28) + seed;
	float plates = 1.0 - abs(2.0 * value_noise(q) - 1.0);
	plates = plates * 0.72 + (1.0 - abs(2.0 * value_noise(q * 2.07 + vec3(7.1, 3.7, 11.9)) - 1.0)) * 0.34;
	float grain = value_noise(p * 1.55 + seed * 1.7);
	// Terraced ledges: a triangle-wave profile over height, warped by the
	// plates so no terrace circles a face as one continuous line. Terrace and
	// grain fade with distance (near_w) — beyond ~200 m they alias into
	// corduroy stripes, so the far faces let the broad plates carry the form.
	float terrace = abs(fract(p.y * 0.21 + plates * 1.35) - 0.5) * 2.0;
	float rock_relief = plates * 1.35
			+ grain * 0.34 * near_w
			+ terrace * 0.55 * cliff * near_w;
	// Snow smooths the rock and replaces it with low wind dunes + sastrugi.
	vec3 s = p * vec3(0.13, 0.3, 0.13) + seed;
	float dune = value_noise(s) * 0.7 + value_noise(s * 2.3) * 0.2;
	return mix(rock_relief, dune * 0.75, snow_w);
}


void fragment() {
	vec3 seed = vec3(seed_offset, seed_offset * 0.37, -seed_offset * 0.61);
	vec3 world_normal = normalize(v_world_normal);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float cliff = smoothstep(0.34, 0.76, slope);
	float bench = 1.0 - smoothstep(0.12, 0.34, slope);

	float broad = fbm(v_world_position * detail_scale * 0.35 + seed);
	float fine = fbm(v_world_position * detail_scale * 1.85 + seed * 1.7);
	float grain = value_noise(v_world_position * detail_scale * 7.4 + seed * 2.3);

	// Rock breaks into slightly tinted plates; two noise bands keep the faces
	// from ever reading as one flat slab of albedo. The broad band runs hotter
	// than the fine so whole buttresses read light or dark from the meadow.
	vec3 color = v_base_color;
	color *= 1.0 + (broad - 0.5) * rock_detail * 1.75;
	color *= 1.0 + (fine - 0.5) * rock_detail * 0.5;

	// Loose soil speckle on the low, gentler ground where dirt would collect.
	float soil = bench * (1.0 - smoothstep(0.5, 0.9, v_altitude));
	color = mix(color, color * mix(0.78, 1.16, grain), soil * dirt_grain);

	// Alpine turf greens the walkable benches near the meadow so the mountain
	// foot marries into the grass field instead of starting as bare rock.
	float alpine = v_flatness * (1.0 - smoothstep(0.02, 0.3, v_altitude)) * (1.0 - cliff);
	color = mix(color, grass_tint.rgb * mix(0.84, 1.12, broad), alpine * grass_blend);

	// Broken sediment bands on the steep faces — a contour that only darkens
	// fragments of any given line so it never circles the peak like a cake.
	float phase = v_world_position.y * 0.092
			+ (broad - 0.5) * 7.0
			+ v_world_position.x * 0.005
			+ seed_offset;
	float contour = pow(0.5 + 0.5 * sin(phase), 9.0);
	// Sediment banding belongs to SOME faces, not all of them — a hard gate
	// keeps whole buttresses clean so the banded ones read as geology, not
	// wallpaper.
	float broken = smoothstep(0.48, 0.72, value_noise(v_world_position * 0.02 + seed * 2.4));
	float strata = contour * broken * strata_strength * cliff
			* smoothstep(0.05, 0.32, v_altitude);
	color *= 1.0 - strata;

	// Cross-cut fractures and ledge lips break long interpolated faces.
	float fracture_x = pow(abs(sin(v_world_position.x * 0.05 + broad * 5.0 + seed_offset)), 16.0);
	float fracture_z = pow(abs(sin(v_world_position.z * 0.045 - fine * 4.0 - seed_offset * 0.7)), 18.0);
	float fracture_gate = smoothstep(0.5, 0.72, value_noise(v_world_position * 0.03 + seed * 3.1));
	float fracture = max(fracture_x, fracture_z) * fracture_gate * cliff;
	color *= 1.0 - fracture * fracture_strength;

	// Talus/scree fans below the cliffs — patchy loose stone, not a smooth ramp.
	float scree_gate = smoothstep(0.45, 0.72,
			fine * 0.6 + value_noise(v_world_position * 0.14 + seed) * 0.4);
	float scree = (1.0 - smoothstep(0.14, 0.5, v_altitude)) * cliff * scree_gate;
	vec3 scree_color = color * mix(0.82, 1.2, value_noise(v_world_position * 0.24 + seed * 1.3));
	color = mix(color, scree_color, scree * scree_strength);

	// Snow wanders down from the summits: pools on up-facing shelves, is scoured
	// thin on wind-blown ridges and cliffs, and follows gullies a little lower.
	float snow_warp = (broad - 0.5) * 0.16 + (fine - 0.5) * 0.05;
	float height_snow = smoothstep(
			snowline - snow_softness, snowline + snow_softness, v_altitude + snow_warp);
	float shelf = mix(0.28, 1.0, smoothstep(0.05, 0.72, world_normal.y));
	float wind_scour = mix(1.0, 0.48, cliff);
	float snow_mask = height_snow * shelf * wind_scour * snow_amount;
	snow_mask *= 1.0 - fracture * 0.42;
	// Rock ribs break through the blanket, but only on genuine cliff faces —
	// gated softly so from the meadow it reads as crag streaked with snow, not
	// speckle noise.
	float rib_break = smoothstep(0.3, 0.62, broad);
	snow_mask *= mix(1.0, rib_break, cliff * cliff * 0.75);
	snow_mask = clamp(snow_mask, 0.0, 0.96);

	// Bumped normal: meso relief the mesh can't carry. Perturbs lighting only —
	// the material zones above stay gated by the stable geometric normal.
	vec3 t_axis = normalize(cross(world_normal,
			abs(world_normal.y) > 0.93 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 b_axis = cross(world_normal, t_axis);
	float eps = 0.55;
	float view_dist = length(v_world_position - CAMERA_POSITION_WORLD);
	float near_w = 1.0 - smoothstep(90.0, 260.0, view_dist);
	float relief_here = surface_relief(v_world_position, snow_mask, cliff, near_w, seed);
	float relief_t = surface_relief(v_world_position + t_axis * eps, snow_mask, cliff, near_w, seed);
	float relief_b = surface_relief(v_world_position + b_axis * eps, snow_mask, cliff, near_w, seed);
	float bump = bump_strength * mix(1.0, 0.45, snow_mask);
	vec3 bumped_normal = normalize(world_normal
			- t_axis * (relief_t - relief_here) / eps * bump
			- b_axis * (relief_b - relief_here) / eps * bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped_normal, 0.0)).xyz);

	// Crevice shading: the same relief field works as baked AO — plate valleys
	// and gully floors darken, crests lighten. Distance-independent, so faces
	// keep structure long after the bump detail falls below pixel size. Up
	// close, per-fragment grain speckle sharpens the impression of real stone.
	float crevice = clamp(relief_here * 0.7, 0.0, 1.0);
	color *= mix(0.68, 1.14, crevice) * mix(1.0, 1.06, snow_mask);
	color *= 1.0 + (grain - 0.5) * 0.3 * near_w * (1.0 - snow_mask);

	// Snow shades faintly blue in its own hollows — the bumped normal decides
	// which dune face looks away from the light. The shadow tint is kept weak
	// and fades with thinning cover, so partial snow reads as white dusting on
	// rock rather than blue stains.
	float snow_face = clamp(0.5 + 0.5 * bumped_normal.y, 0.0, 1.0);
	float shadow_reach = mix(0.5, 1.0, snow_face * snow_mask);
	vec3 snow_color = mix(snow_shadow_tint.rgb, snow_tint.rgb, shadow_reach);
	snow_color *= mix(0.88, 1.04, broad);
	color = mix(color, snow_color, snow_mask);

	// A whisper of aerial haze on the highest, farthest rock; Godot's own fog
	// finishes the depth cue so the near slopes stay saturated.
	color = mix(color, haze_tint.rgb, haze_amount * smoothstep(0.35, 1.0, v_altitude));

	ALBEDO = color;
	ROUGHNESS = mix(0.96, 0.72, snow_mask);
	SPECULAR = mix(0.06, 0.2, snow_mask);
	EMISSION = color * fill_amount * shadow_fill.rgb;
	float fresnel = 1.0 - clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0);
	EMISSION += haze_tint.rgb * pow(fresnel, 4.0) * 0.012;
}
