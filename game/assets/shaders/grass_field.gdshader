shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, specular_schlick_ggx;
// Photoreal meadow field. Every MultiMesh instance is one unit-height blade
// strip on an identity transform; this shader wraps the tile toroidally
// around the camera, plants blades on the height map, and builds ALL the
// structure a real sward has:
//   - rounded cross-blade normals (flat cards shade like 3-D blades)
//   - clump-coherent lean: ~40 cm cells share a direction/strength, so the
//     field mats and swirls like real grass instead of combing one way
//   - population roles per blade: normal / flopped / dead-brown / seed stalk
//   - big clumped height + width variation, mid-blade kinks on broken blades
//   - realistic colour: cool dark bases, dry tips, brown dead blades, patch
//     and clump hue drift
//   - layered wind (broad gusts + flutter) on top of the structural lean
//   - dithered pop at the tile edge (no shrinking band = no LOD seam)
//   - trample: the field parts around gf_player_pos (global, set by Player)
// Near and far carpets share this shader with different tile/height/width.

global uniform vec3 gf_player_pos;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float terrain_size = 480.0;
uniform float water_level = 0.0;
uniform float tile = 56.0;
uniform float fade_start = 22.0;
uniform float fade_end = 27.0;

uniform float blade_height = 0.42;              // metres, clump mean
uniform float width_scale = 1.0;                // far field widens blades
uniform float blade_bend : hint_range(0.0, 2.0) = 1.0;
uniform float round_amount : hint_range(0.0, 1.6) = 1.15;

uniform vec3 color_deep : source_color = vec3(0.055, 0.11, 0.035);
uniform vec3 color_mid : source_color = vec3(0.155, 0.315, 0.065);
uniform vec3 color_tip : source_color = vec3(0.40, 0.53, 0.16);
uniform vec3 color_dry : source_color = vec3(0.50, 0.42, 0.18);
uniform vec3 color_dead : source_color = vec3(0.30, 0.24, 0.14);
uniform vec3 color_straw : source_color = vec3(0.55, 0.48, 0.26);

uniform vec2 wind_dir = vec2(0.75, 0.55);
uniform float wind_speed = 1.1;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.28;

uniform float trample_radius = 1.3;

varying float v_tip;
varying float v_gust;
varying float v_visibility;
varying float v_ao;
varying float v_rough;
varying vec3 v_col;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

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

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	float v = UV.y;                  // 0 root → 1 tip
	float side = UV.x * 2.0 - 1.0;   // -1 → 1 across the width
	v_tip = v;

	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - instance_origin;
	vec2 camera_xz = CAMERA_POSITION_WORLD.xz;

	// Toroidal wrap: the blade tile follows the camera — dense cover
	// wherever you stand, zero per-frame CPU.
	vec2 relative = instance_origin.xz - camera_xz;
	vec2 wrapped = mod(relative + tile * 0.5, tile) - tile * 0.5;
	vec2 planted = camera_xz + wrapped;

	// Per-blade randoms (stable: derived from the authored origin).
	float rnd = hash21(instance_origin.xz * 7.31 + 3.1);
	float rnd2 = hash21(instance_origin.xz * 3.77 + 11.7);
	float rnd3 = hash21(instance_origin.xz * 5.13 + 27.3);
	float rnd4 = hash21(instance_origin.xz * 9.41 + 51.7);
	float yaw = rnd * 6.2831853;

	// Clump cell (~40 cm): blades in a cell share direction, height, hue —
	// this is what kills the "combed one way" look.
	vec2 cell = floor(planted * 2.6);
	float clump_ang = hash21(cell * 1.71 + 7.7) * 6.2831853;
	float clump_lean = hash21(cell * 2.33 + 19.1);
	float clump_tone = hash21(cell * 4.91 + 3.3);
	vec2 clump_dir = vec2(cos(clump_ang), sin(clump_ang));
	vec2 blade_dir = vec2(cos(rnd * 25.13), sin(rnd * 25.13));
	vec2 lean_dir = normalize(mix(clump_dir, blade_dir, 0.35));

	// Height map: R = terrain height, G = terrain normal.y.
	vec2 tuv = (planted + terrain_size * 0.5) / terrain_size;
	vec2 hg = textureLod(height_map, tuv, 0.0).rg;
	float margin = terrain_size * 0.5 - 14.0;
	float alive = step(water_level + 0.35, hg.r)
			* step(0.72, hg.g)
			* step(abs(planted.x), margin)
			* step(abs(planted.y), margin);
	// Dithered pop: each blade owns a die-distance inside the fade band.
	// Full-size blades thin out stochastically — no shrinking seam band.
	float radial = 1.0 - smoothstep(fade_start, fade_end, length(wrapped));
	v_visibility = alive * step(rnd4 * 0.999, radial);

	// ---- Population roles ----
	float flopped = step(rnd3, 0.05);                          // 5% matted flat
	float dead = step(0.05, rnd3) * step(rnd3, 0.095);         // 4.5% brown dead
	float stalk = step(0.965, rnd3);                           // 3.5% seed stalks
	float broken = step(0.90, rnd3) * (1.0 - stalk);           // kinked mid-blade

	// Clumped height: short worn patches and tall stands, then per blade.
	float height = blade_height * (0.62 + 0.76 * clump_tone) * (0.72 + 0.56 * rnd2);
	height *= 1.0 + stalk * 0.95;          // stalks stand well proud
	local.y *= height;
	local.x *= width_scale * (0.75 + 0.5 * rnd4) * (1.0 - stalk * 0.35);

	// ---- Wind: broad rolling gusts + per-blade flutter ----
	vec2 wdir = normalize(wind_dir);
	vec2 wcross = vec2(-wdir.y, wdir.x);
	float march = dot(planted, wdir) * 0.06 - TIME * wind_speed;
	float cross_wave = dot(planted, wcross) * 0.03 + TIME * 0.33;
	float broad = sin(march) * 0.72 + sin(cross_wave) * 0.28;
	v_gust = smoothstep(-0.5, 0.8, broad);
	v_gust *= v_gust;
	float flutter = sin(TIME * (3.2 + rnd2 * 1.4) + rnd * 40.0 + dot(planted, wcross) * 0.25);
	flutter *= 1.0 + stalk * 0.8;          // stalks tremble more

	float tipw = pow(v, 1.6);
	// Structural lean (metres at tip): clump base + role modifiers.
	float droop = blade_bend * height * (0.10 + 0.45 * clump_lean) * (0.6 + 0.8 * rnd2);
	droop *= 1.0 - stalk * 0.7;            // stalks stay upright
	droop += flopped * height * 0.85;      // flopped: tip near the ground
	droop += dead * height * 0.35;         // dead blades sag
	vec2 lean = lean_dir * (droop * tipw);
	// Broken blades kink sharply past the midpoint.
	lean += lean_dir * (broken * height * 0.5 * max(0.0, v - 0.45));
	// Wind rides ON TOP of structure — light idle sway, strong in gusts.
	lean += wdir * ((0.008 + v_gust * wind_strength) * tipw);
	lean += wcross * (flutter * 0.022 * tipw);

	// Rounded cross-blade normal — a flat card shades like a cylinder.
	float ang = side * round_amount;
	vec3 nrm = vec3(sin(ang), 0.0, cos(ang));
	nrm = normalize(mix(nrm, vec3(0.0, 1.0, 0.0), v * 0.25));
	nrm.xz = rot2(nrm.xz, yaw);
	nrm.xz -= lean * 0.6;
	nrm = normalize(nrm);

	local *= v_visibility;                 // culled blades: true zero area
	local.xz = rot2(local.xz, yaw);

	vec3 world = vec3(planted.x, hg.r, planted.y) + local;
	world.xz += lean * v_visibility;
	// Leaning is an arc, not a shear: the tip comes DOWN as it goes out.
	float lean_len = length(lean);
	world.y -= min(lean_len * lean_len * 0.6 / max(height, 0.05), height * 0.8) * v_visibility;

	// ---- Trample: part around the player ----
	vec2 to_blade = world.xz - gf_player_pos.xz;
	float pd = length(to_blade);
	float trample = 1.0 - smoothstep(0.15, trample_radius, pd);
	trample *= step(abs(gf_player_pos.y - hg.r), 3.0);   // only when grounded near
	vec2 away = pd > 0.001 ? to_blade / pd : wcross;
	world.xz += away * trample * 0.45 * tipw * v_visibility;
	world.y -= trample * height * 0.55 * tipw * v_visibility;

	VERTEX = world;
	NORMAL = nrm;

	// ---- Colour ----
	float patch = vnoise(planted * 0.02);
	float dry_field = smoothstep(0.6, 0.86, vnoise(planted * 0.009 + vec2(19.0, -31.0)));
	vec3 g = mix(color_deep, color_mid, smoothstep(0.0, 0.55, v));
	g = mix(g, color_tip, smoothstep(0.45, 1.0, v));
	// Clump + patch tone drift, then per-blade dry tips.
	g *= 0.80 + 0.30 * patch;
	g *= 0.88 + 0.24 * clump_tone;
	float dry_tip = smoothstep(0.55, 0.95, rnd2) * 0.30 + dry_field * 0.30;
	g = mix(g, color_dry, dry_tip * smoothstep(0.35, 1.0, v));
	// Seed stalks turn straw over the top half.
	g = mix(g, color_straw, stalk * smoothstep(0.45, 0.8, v));
	// Dead blades are brown their full length.
	g = mix(g, color_dead * (0.75 + 0.5 * rnd2), dead);
	v_col = g;
	v_ao = mix(0.5, 1.0, smoothstep(0.0, 0.5, v));
	v_rough = mix(0.92, 0.66, smoothstep(0.3, 1.0, v)) + dead * 0.15;
}

void fragment() {
	// No discard here on purpose: rejected blades are collapsed to zero area
	// in vertex() (never rasterized), and a discard would disable early-Z —
	// ruinous under this much blade overdraw.
	ALBEDO = v_col * v_ao;
	ROUGHNESS = v_rough;
	SPECULAR = 0.22;
	// Sunlight bleeding through the blade — strongest near the tip.
	BACKLIGHT = v_col * (0.24 + 0.30 * v_tip);
	// Tiny floor keeps night grass from crushing to pure black.
	EMISSION = v_col * 0.012;
	RIM = 0.09 * smoothstep(0.35, 1.0, v_tip);
	RIM_TINT = 0.4;
}
