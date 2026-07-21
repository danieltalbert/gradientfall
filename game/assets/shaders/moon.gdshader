shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform float visibility : hint_range(0.0, 1.0) = 0.0;
uniform vec4 moon_color : source_color = vec4(0.76, 0.84, 1.0, 1.0);

varying vec2 v_uv;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

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
	float disc = 1.0 - smoothstep(0.46, 0.495, d);
	float halo = 1.0 - smoothstep(0.30, 0.74, d);
	float craters = noise(v_uv * 15.0) * 0.65 + noise(v_uv * 43.0) * 0.35;
	float limb = sqrt(max(0.0, 1.0 - d * d * 3.9));
	vec3 surface = moon_color.rgb * (0.72 + craters * 0.22) * (0.72 + limb * 0.28);
	ALBEDO = surface;
	EMISSION = surface * (1.6 + disc * 0.65);
	ALPHA = clamp((disc + halo * 0.20) * visibility, 0.0, 1.0);
}
