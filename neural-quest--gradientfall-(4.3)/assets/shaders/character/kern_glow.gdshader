shader_type spatial;
render_mode unshaded, cull_disabled;
// Kern's arcane glow — the hand-mark sigil, the latent threads that climb his
// skin, the sword pommel sigil. This is the "First Model showing through": at
// rest it's the faintest ember (he looks like an ordinary traveller), and it
// blazes as `awaken` rises (near ancient machinery / knowledge charge /
// hallucination zones). A pulse of light flows along each thread (UV.y = root
// -> tip) so the magic reads as *alive*, not a static decal.

// Shared awaken level, 0 (disguised) .. 1 (fully lit). Driven by kern_visual.
uniform float awaken : hint_range(0.0, 1.0) = 0.12;
uniform vec4 glow_lo : source_color = vec4(1.0, 0.66, 0.16, 1.0);  // ember gold
uniform vec4 glow_hi : source_color = vec4(0.55, 0.92, 1.0, 1.0);  // charged cyan
uniform float base_energy : hint_range(0.0, 6.0) = 0.8;
uniform float rest_floor : hint_range(0.0, 0.5) = 0.16;
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.4;
uniform float flow_freq : hint_range(0.0, 24.0) = 7.0;

varying float v_along;

void vertex() {
	v_along = UV.y;
}

void fragment() {
	// A bright bead of light travels root->tip along the thread.
	float flow = 0.5 + 0.5 * sin(TIME * pulse_speed - v_along * flow_freq);
	float breathe = 0.85 + 0.15 * sin(TIME * 1.3);
	float lvl = clamp(awaken, 0.0, 1.0);
	// Gold at rest, shifting cyan-white as it charges.
	vec3 col = mix(glow_lo.rgb, glow_hi.rgb, lvl * lvl);
	float energy = base_energy * (rest_floor + lvl * 0.9) * (0.6 + 0.4 * flow) * breathe;
	ALBEDO = col;
	EMISSION = col * energy;
}
