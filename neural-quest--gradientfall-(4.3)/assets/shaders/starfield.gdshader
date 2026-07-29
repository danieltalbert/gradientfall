shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform float visibility : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cool_color : source_color = vec4(0.60, 0.76, 1.0, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.82, 0.48, 1.0);

varying float v_seed;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mat4 billboard_model = MODEL_MATRIX;
	billboard_model[0].xyz = INV_VIEW_MATRIX[0].xyz * sx;
	billboard_model[1].xyz = INV_VIEW_MATRIX[1].xyz * sy;
	billboard_model[2].xyz = INV_VIEW_MATRIX[2].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard_model;
	v_seed = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	float core = 1.0 - smoothstep(0.018, 0.095, d);
	float halo = 1.0 - smoothstep(0.04, 0.46, d);
	float cross = exp(-abs(p.x) * 34.0) * exp(-abs(p.y) * 5.0)
			+ exp(-abs(p.y) * 34.0) * exp(-abs(p.x) * 5.0);
	float twinkle = 0.72 + 0.28 * sin(TIME * (0.8 + v_seed * 2.1) + v_seed * 41.0);
	vec3 col = mix(cool_color.rgb, warm_color.rgb, fract(v_seed * 7.31));
	ALBEDO = col;
	EMISSION = col * (1.65 + core * 3.2);
	ALPHA = clamp((core + halo * 0.42 + cross * 0.18) * twinkle * visibility, 0.0, 1.0);
}
