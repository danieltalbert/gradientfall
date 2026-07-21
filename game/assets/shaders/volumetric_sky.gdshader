shader_type sky;

// ============================================================================
//  Gradientfall — volumetric raymarched sky (Datasedge over the Meadows)
// ----------------------------------------------------------------------------
//  Photoreal-volumetric cloudscape rendered entirely in the sky pass, so the
//  clouds live at true altitude and infinity: they recede to a life-sized
//  horizon, drift with a real wind, and evolve over minutes. Nothing here
//  touches scene geometry, so the grass/mountain lighting the other build
//  sessions are tuning against is left completely alone — SkyCycle keeps
//  driving the sun/ambient/fog exactly as before and only *feeds* this shader
//  its time-of-day palette so the horizon colour still meshes with the vistas.
//
//  Uniform ownership (two writers, disjoint sets, no races):
//    * SkyCycle    -> atmosphere + time-of-day (sky colours, sun, moon, night)
//    * CloudLayer  -> weather (coverage, wind, density, layer heights, detail)
//
//  Model: an eye-local spherical shell between `cloud_base`..`cloud_top`. The
//  ray is intersected against the inner/outer shells; the segment between them
//  is the slab we integrate. Noise is sampled in WORLD space (anchored to the
//  camera world position) so the cloudscape stays put as Kern walks.
// ============================================================================

// ---- Atmosphere / time-of-day (written by SkyCycle) ------------------------
uniform vec3 sky_top_color : source_color = vec3(0.09, 0.34, 0.72);
uniform vec3 sky_horizon_color : source_color = vec3(0.55, 0.72, 0.86);
uniform vec3 ground_color : source_color = vec3(0.18, 0.22, 0.16);
uniform vec3 sun_direction = vec3(0.35, 0.72, 0.28);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
uniform float sun_energy : hint_range(0.0, 4.0) = 1.4;
uniform vec3 moon_direction = vec3(-0.4, 0.55, 0.3);
uniform vec3 moon_color : source_color = vec3(0.55, 0.66, 0.95);
uniform float moon_energy : hint_range(0.0, 2.0) = 0.0;
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;   // 1 = full day, 0 = night
uniform float haze_strength : hint_range(0.0, 1.0) = 0.5;

// ---- Cloud weather (written by CloudLayer) ---------------------------------
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_density : hint_range(0.0, 4.0) = 1.35;
uniform float cloud_base = 620.0;         // metres above the meadow
uniform float cloud_top = 1650.0;
uniform vec2 wind_dir = vec2(0.86, 0.51);
uniform float wind_speed = 34.0;          // metres / second of drift
uniform float detail_strength : hint_range(0.0, 1.0) = 0.62;   // edge fluff/erosion
uniform float shape_scale = 1.0;          // >1 = smaller, busier clouds
uniform float cirrus_amount : hint_range(0.0, 1.0) = 0.35;     // high thin veil
uniform float storminess : hint_range(0.0, 1.0) = 0.0;         // darker, taller, denser

// ---- Quality ---------------------------------------------------------------
const int PRIMARY_STEPS = 96;
const int LIGHT_STEPS = 6;
const float PLANET_RADIUS = 4.0e6;         // ~4000 km: clouds recede ~115 km to a life-sized horizon, good float precision
const float MAX_MARCH = 62000.0;          // cap the grazing-ray path length
const float LIGHT_MARCH_LEN = 640.0;      // sun-ward optical-depth probe distance

// ---------------------------------------------------------------------------
//  Hash + value noise (3D). Same family as the meadow shaders for consistency.
// ---------------------------------------------------------------------------
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	float near_z = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
	float far_z = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
	return mix(near_z, far_z, f.z);
}

// Fractal Brownian motion — the broad billowing mass.
float fbm(vec3 p, int octaves) {
	float total = 0.0;
	float amplitude = 0.5;
	float weight = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += value_noise(p) * amplitude;
		weight += amplitude;
		p = p * 2.02 + vec3(11.7, 5.2, 19.3);
		amplitude *= 0.5;
	}
	return total / max(weight, 0.0001);
}

// Ridged fBm — sharp cauliflower crests. 1 - |2n-1| folds the noise into ridges.
float ridged_fbm(vec3 p, int octaves) {
	float total = 0.0;
	float amplitude = 0.5;
	float weight = 0.0;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(value_noise(p) * 2.0 - 1.0);
		n *= n;
		total += n * amplitude;
		weight += amplitude;
		p = p * 2.13 + vec3(3.1, 17.9, 7.4);
		amplitude *= 0.5;
	}
	return total / max(weight, 0.0001);
}

float remap(float v, float a, float b, float c, float d) {
	return c + (clamp(v, min(a, b), max(a, b)) - a) * (d - c) / (b - a + 0.00001);
}

// Henyey-Greenstein phase — forward g gives the sun-side silver lining.
float henyey_greenstein(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * 3.14159265 * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5));
}

// Ray from the on-axis eye (0, eye_h, 0) vs the shell at altitude `alt` above
// the planet surface. Factored form (|oc|-r)(|oc|+r) instead of |oc|²-r²:
// at planet radii, the squared form loses ~1e6 m to float32 cancellation,
// while the factors here stay small and exact. Returns near/far t in .x/.y.
vec2 shell_hits(float eye_h, vec3 dir, float alt) {
	float b = (PLANET_RADIUS + eye_h) * dir.y;
	float c = (eye_h - alt) * (2.0 * PLANET_RADIUS + eye_h + alt);
	float disc = b * b - c;
	if (disc < 0.0) {
		return vec2(1.0, -1.0);
	}
	disc = sqrt(disc);
	return vec2(-b - disc, -b + disc);
}

// Vertical density profile: rounded, wind-anchored base rising into a billowing
// top that anvils out. `type` (0..1) leans stratus->towering-cumulus.
float height_profile(float h, float type) {
	float bottom = smoothstep(0.0, 0.11 + type * 0.05, h);
	float top = 1.0 - smoothstep(0.55 - type * 0.12, 1.0, h);
	// A little extra mass mid-column so towers read three-dimensional.
	float belly = 1.0 - abs(h - 0.42) * 0.7;
	return clamp(bottom * top * belly, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
//  Cloud density at a world-space sample. `detail` toggles the expensive
//  erosion octaves (cheap version used during the sun light-march).
// ---------------------------------------------------------------------------
float cloud_density_at(vec3 world_pos, float height_frac, bool detail) {
	vec3 wind = vec3(wind_dir.x, 0.0, wind_dir.y) * wind_speed * TIME;
	// Two flow rates: horizontal drift + a slow vertical "boil" so masses
	// visibly grow and dissolve rather than sliding rigidly.
	vec3 p = (world_pos + wind) * (0.00035 * shape_scale);
	vec3 boil = vec3(0.0, TIME * 0.006, 0.0);

	vec3 sp = p + boil;
	float shape;
	if (detail) {
		// Domain warp bends the shape noise into curled, ridged lobes, and the
		// ridged octaves cut the cauliflower crests into the silhouette.
		vec3 warp = vec3(
			fbm(p * 0.6 + boil, 3),
			fbm(p * 0.6 + boil + vec3(31.0, 0.0, 11.0), 3),
			fbm(p * 0.6 + boil + vec3(0.0, 47.0, 23.0), 3)
		) - 0.5;
		sp += warp * 0.85;
		shape = mix(fbm(sp, 4), ridged_fbm(sp * 1.9, 3), 0.42);
	} else {
		// Sun-march probe: coarse mass only. The soft mismatch vs. the warped
		// primary field just blurs self-shadow contact, which reads natural.
		shape = fbm(sp, 3);
	}

	// Big low-frequency cells make broad clear/cloudy regions across the sky.
	float region = fbm(world_pos * 0.00006 + vec3(0.0, 0.0, TIME * 0.0004), 3);
	float local_cover = clamp(cloud_coverage * remap(region, 0.25, 0.85, 0.35, 1.35), 0.0, 1.0);

	float type = clamp(0.35 + storminess * 0.5 + (region - 0.5) * 0.4, 0.0, 1.0);
	float profile = height_profile(height_frac, type);

	// Coverage carve: raise the noise floor with coverage. Storms fill in more.
	float base = remap(shape * profile, 1.0 - local_cover, 1.0, 0.0, 1.0);
	base *= profile;

	if (!detail) {
		return clamp(base, 0.0, 1.0);
	}

	// Erosion — subtract high-frequency detail from the edges to sculpt fluff.
	float erosion = fbm(sp * 6.4 + wind * 0.0004 + vec3(0.0, 0.0, TIME * 0.02), 3);
	float wispy = fbm(sp * 15.0, 2);
	float carve = mix(erosion, wispy, 0.35) * detail_strength;
	// Edges (low base) erode most; dense cores stay solid.
	base = remap(base, carve * (1.0 - height_frac * 0.4), 1.0, 0.0, 1.0);

	return clamp(base, 0.0, 1.0);
}

// March a few steps toward the sun; return light transmittance (0=shadowed).
float light_march(vec3 pos, vec3 sun_dir, vec3 center, float shell_lo, float shell_span) {
	float optical = 0.0;
	float step_len = LIGHT_MARCH_LEN / float(LIGHT_STEPS);
	for (int i = 0; i < LIGHT_STEPS; i++) {
		vec3 sp = pos + sun_dir * (float(i) + 0.5) * step_len;
		float hf = clamp((length(sp - center) - shell_lo) / shell_span, 0.0, 1.0);
		optical += cloud_density_at(sp, hf, false) * step_len;
	}
	// Beer's law with a multiple-scatter tail: the primary term digs deep
	// shadow into the billows (that's what sculpts the ridges); the wide weak
	// term keeps thick cloud from going dead black.
	float beer = exp(-optical * 0.003 * cloud_density);
	float beer2 = exp(-optical * 0.003 * cloud_density * 0.22) * 0.55;
	return max(beer, beer2);
}

// ---------------------------------------------------------------------------
//  A high, thin cirrus veil rendered analytically (2D), layered above the
//  volumetric cumulus for that "whole sky has weather" read.
// ---------------------------------------------------------------------------
float cirrus_veil(vec3 dir) {
	if (dir.y < 0.02) {
		return 0.0;
	}
	// Project the ray onto a very high plane and streak the noise with the wind.
	vec3 hit = dir * (7000.0 / max(dir.y, 0.02));
	vec2 uv = hit.xz * 0.00022 + wind_dir * TIME * 0.004;
	float streak = fbm(vec3(uv.x * 0.6, uv.y * 3.4, 0.0), 4);
	streak = smoothstep(0.52, 0.85, streak);
	float fade = smoothstep(0.02, 0.35, dir.y);
	return streak * fade * cirrus_amount;
}

// ---------------------------------------------------------------------------
//  Base atmosphere gradient + sun/moon glow (cheap; runs every pass).
// ---------------------------------------------------------------------------
vec3 atmosphere(vec3 dir) {
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 sky = mix(sky_horizon_color, sky_top_color, pow(up, 0.42));

	// Sun aureole + crisp disk.
	float sd = max(dot(dir, normalize(sun_direction)), 0.0);
	sky += sun_color * pow(sd, 6.0) * 0.20 * (0.2 + sun_energy);
	sky += sun_color * pow(sd, 220.0) * 1.4 * sun_energy;
	sky += sun_color * smoothstep(0.99965, 0.99992, sd) * 7.0 * max(sun_energy, 0.15);

	// The moon disc itself is drawn by CelestialLayer's billboard; here we only
	// contribute its faint directional light to the clouds (via light_march),
	// so no moon glow is added to the atmosphere gradient to avoid a second moon.

	// Thicken haze toward the horizon so it meets the vistas' fog cleanly.
	float horizon = pow(1.0 - up, 5.0) * haze_strength;
	sky = mix(sky, sky_horizon_color, clamp(horizon, 0.0, 0.85));

	// Below the horizon reads as hazy ground, not black.
	sky = mix(ground_color, sky, smoothstep(-0.05, 0.02, dir.y));
	return sky;
}

// ---------------------------------------------------------------------------
//  Full volumetric cloud integration for a ray. Returns scattered light in
//  .rgb and remaining transmittance in .a.
// ---------------------------------------------------------------------------
vec4 march_clouds(float eye_h, vec3 dir, float jitter) {
	// The shells surround the eye, so every direction eventually hits them —
	// including straight down. Gate to the sky hemisphere: no clouds below the
	// horizon line (the atmosphere/vistas own that band).
	if (dir.y < 0.0015) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	// Eye-local spherical shells: planet centre sits one radius below the eye.
	// The eye is inside both shells, so going up we cross the inner (cloud base)
	// then the outer (cloud top); that segment is the slab we integrate.
	vec3 origin = vec3(0.0, eye_h, 0.0);
	vec3 center = vec3(0.0, -PLANET_RADIUS, 0.0);
	float shell_lo = PLANET_RADIUS + cloud_base;
	float shell_span = cloud_top - cloud_base;

	vec2 inner = shell_hits(eye_h, dir, cloud_base);
	vec2 outer = shell_hits(eye_h, dir, cloud_top);

	float t_start = max(inner.y, 0.0);   // cross the base going up
	float t_end = outer.y;               // cross the top going up
	if (t_end <= t_start) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	t_end = min(t_end, t_start + MAX_MARCH);

	float seg = t_end - t_start;
	float step_len = seg / float(PRIMARY_STEPS);
	float t = t_start + step_len * jitter;

	vec3 sun_dir = normalize(sun_direction);
	float cos_theta = dot(dir, sun_dir);
	// Dual-lobe phase: strong forward silver lining + gentle wrap.
	float phase = mix(henyey_greenstein(cos_theta, 0.82),
			henyey_greenstein(cos_theta, -0.28), 0.28);
	phase = max(phase, 0.10);

	// Cloud ambient: bright sky from above, cool/dark from below.
	vec3 amb_top = sky_top_color * (0.55 + 0.45 * day_amount) + sun_color * 0.05 * day_amount;
	vec3 amb_bottom = sky_horizon_color * 0.25 * (0.4 + 0.6 * day_amount);
	amb_bottom += moon_color * 0.06 * moon_energy;
	vec3 sun_light = sun_color * sun_energy * 2.2;
	vec3 moon_light = moon_color * moon_energy * 0.9;

	float transmittance = 1.0;
	vec3 scattered = vec3(0.0);

	for (int i = 0; i < PRIMARY_STEPS; i++) {
		if (transmittance < 0.02) {
			break;
		}
		vec3 pos = origin + dir * t;
		float hf = clamp((length(pos - center) - shell_lo) / shell_span, 0.0, 1.0);
		// `pos` carries the true world altitude (origin.y = camera height); its
		// horizontal frame is eye-local, which for a 480 m meadow is an
		// imperceptible parallax — clouds read as world-anchored under wind.
		float density = cloud_density_at(pos, hf, true);

		if (density > 0.001) {
			float d = density * cloud_density;
			float sun_t = light_march(pos, sun_dir, center, shell_lo, shell_span);
			float moon_t = moon_energy > 0.001
					? light_march(pos, normalize(moon_direction), center, shell_lo, shell_span)
					: 0.0;
			// Powder term darkens dense-facing edges (multiple-scatter cue).
			float powder = 1.0 - exp(-d * step_len * 0.02);
			vec3 direct = (sun_light * sun_t + moon_light * moon_t) * phase * powder;
			vec3 ambient = mix(amb_bottom, amb_top, hf);
			vec3 lum = direct + ambient;

			float sample_sigma = d * step_len * 0.0016;
			float sample_t = exp(-sample_sigma);
			// Energy-conserving front-to-back integration.
			scattered += transmittance * lum * (1.0 - sample_t);
			transmittance *= sample_t;
		}
		t += step_len;
	}

	// Fade distant clouds into the horizon haze (aerial perspective).
	float horizon_fade = smoothstep(0.14, 0.015, dir.y) * haze_strength;
	scattered = mix(scattered, sky_horizon_color * (1.0 - transmittance), horizon_fade * 0.8);
	transmittance = mix(transmittance, 1.0, horizon_fade * 0.5);

	return vec4(scattered, transmittance);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Eye height carries the camera's world altitude so perspective shifts as
	// Kern climbs — clamped so extreme heights stay stable.
	float eye_h = clamp(POSITION.y, -20.0, 500.0);

	vec3 sky = atmosphere(dir);

	// Godot forbids early `return` inside sky(), so the cubemap fast path and
	// the full raymarch live in one if/else.
	if (AT_CUBEMAP_PASS) {
		// Cheap reflection sky: no raymarch, just tint by coverage so water
		// reflects a plausible cloudy sky without paying the volumetric cost.
		float veil = cirrus_veil(dir) * 0.5;
		vec3 flat_cloud = mix(sky_horizon_color, sky_top_color, 0.5)
				* (0.75 + 0.35 * day_amount);
		float cover = clamp(cloud_coverage * 0.6 * smoothstep(-0.05, 0.25, dir.y), 0.0, 0.7);
		COLOR = mix(sky, flat_cloud, cover + veil);
	} else {
		// Blue-ish jitter from the ray direction + time breaks up step banding.
		float jitter = fract(hash13(dir * 977.0) + TIME * 0.61);

		// High cirrus first (behind cumulus is fine — it's a thin tint).
		float cirrus = cirrus_veil(dir);
		vec3 cirrus_col = mix(sky_horizon_color, vec3(1.0), 0.6) * (0.6 + 0.6 * day_amount);
		cirrus_col += sun_color * pow(max(dot(dir, normalize(sun_direction)), 0.0), 8.0) * 0.4 * sun_energy;
		sky = mix(sky, cirrus_col, cirrus * 0.7);

		// Volumetric cumulus.
		vec4 clouds = march_clouds(eye_h, dir, jitter);
		vec3 result = sky * clouds.a + clouds.rgb;

		COLOR = max(result, vec3(0.0));
	}
}
