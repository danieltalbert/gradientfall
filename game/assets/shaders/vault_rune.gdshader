shader_type spatial;
// depth_prepass_alpha: the shader writes ALPHA, which makes every surface
// using it transparent. Without a prepass the glass-tube columns sort badly
// against each other; with it they behave like solids where alpha is 1.
render_mode unshaded, cull_disabled, depth_prepass_alpha;
// The Perceptron Vault's one light-language: every glowing surface in the
// dungeon — signal conduits, weight glyphs, sum columns, threshold beams,
// door runes, the Gatekeeper's charge core — is this shader with different
// uniforms. Unshaded on purpose: these read as light sources embedded in the
// stone, so they must stay bright inside a sealed vault where the sun never
// reaches (GDD §10 "nothing pops in or out without a transition").
//
// Three independent effects, each switchable to zero cost by its amount
// uniform:
//   * pulse — a slow breathing brightness (idle runes)
//   * flow  — a travelling bright band along local +Y (signal in a conduit)
//   * fill  — a hard cutoff along local Y, so one mesh can act as a meter
//             (sum columns, the Gatekeeper's charge core)
//
// Conventions: meshes are authored with their long axis on local Y, and
// `fill` is a 0..1 fraction of that axis measured from the bottom. Alpha
// below `fill` is 1 and above it is `dim_alpha`, so an unfilled column still
// reads as a glass tube rather than vanishing.

group_uniforms color;
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.32, 1.0);
// Multiplies the final emission. Above 1.0 the bloom in the world
// environment takes over and the surface blooms — that is the intent.
uniform float energy : hint_range(0.0, 8.0) = 2.4;

group_uniforms pulse;
// Fraction of `energy` that breathes (0 = steady, 1 = full on/off).
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.18;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.6;
// Phase offset in radians, so neighbouring runes do not breathe in lockstep.
uniform float pulse_phase = 0.0;

group_uniforms flow;
// Brightness of the travelling band, in multiples of `energy`.
uniform float flow_amount : hint_range(0.0, 3.0) = 0.0;
uniform float flow_speed = 1.2;
// Bands per meter of local Y. Lower = longer, lazier pulses of signal.
uniform float flow_density = 0.35;

group_uniforms meter;
// 1.0 = the whole mesh is lit. Below that, the part above the cutoff drops
// to dim_alpha — the mesh becomes a fill meter.
uniform float fill : hint_range(0.0, 1.0) = 1.0;
// Local-Y extent (meters) the fill fraction is measured against. Set from
// code to the mesh's height so `fill` stays a plain 0..1 fraction.
uniform float fill_height = 1.0;
// Local-Y coordinate of the mesh's bottom. BoxMesh is origin-centered, so
// this is normally -height/2.
uniform float fill_base = -0.5;
uniform float dim_alpha : hint_range(0.0, 1.0) = 0.12;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float e = energy;

	// Breathing. sin() is remapped to 0..1 so pulse_amount is a clean
	// fraction of energy rather than a signed swing.
	if (pulse_amount > 0.001) {
		float p = sin(TIME * pulse_speed + pulse_phase) * 0.5 + 0.5;
		e *= 1.0 - pulse_amount + pulse_amount * p;
	}

	// Travelling band: a sawtooth along local Y, sharpened by smoothstep so
	// the band has a bright head and a soft tail — signal moving, not a
	// blinking stripe.
	if (flow_amount > 0.001) {
		float band = fract(v_local.y * flow_density - TIME * flow_speed);
		e += energy * flow_amount * smoothstep(0.55, 1.0, band);
	}

	float alpha = 1.0;
	if (fill < 0.999) {
		// Height of the fill line in local space.
		float cut = fill_base + fill * fill_height;
		// Two-pixel-ish soft edge so the meter's top does not crawl and
		// alias as it rises.
		float lit = 1.0 - smoothstep(cut - 0.02, cut + 0.02, v_local.y);
		alpha = mix(dim_alpha, 1.0, lit);
		e *= mix(0.25, 1.0, lit);
	}

	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * e;
	ALPHA = glow_color.a * alpha;
}
