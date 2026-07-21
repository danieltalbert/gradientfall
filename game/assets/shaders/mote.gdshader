shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Soft pollen/firefly sprite. The previous StandardMaterial rendered every
// mote as a tiny square; this analytic radial mask keeps only a luminous core
// and feathered halo, with a gentle non-synchronized shimmer in world space.

uniform vec4 core_color : source_color = vec4(1.0, 0.82, 0.34, 0.82);
uniform vec4 halo_color : source_color = vec4(1.0, 0.62, 0.16, 0.26);

varying vec3 v_wpos;

void vertex() {
	mat4 billboard_model = MODEL_MATRIX;
	billboard_model[0].xyz = INV_VIEW_MATRIX[0].xyz;
	billboard_model[1].xyz = INV_VIEW_MATRIX[1].xyz;
	billboard_model[2].xyz = INV_VIEW_MATRIX[2].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard_model;
	v_wpos = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	float core = 1.0 - smoothstep(0.035, 0.16, d);
	float halo = 1.0 - smoothstep(0.08, 0.49, d);
	float seed = fract(sin(dot(floor(v_wpos * 2.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float shimmer = 0.68 + 0.32 * sin(TIME * (1.7 + seed * 2.4) + seed * 17.0);
	ALBEDO = mix(halo_color.rgb, core_color.rgb, core);
	EMISSION = ALBEDO * (1.4 + core * 1.8) * shimmer;
	ALPHA = (halo * halo_color.a + core * core_color.a) * shimmer;
}
