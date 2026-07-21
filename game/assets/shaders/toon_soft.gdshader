shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// SOFT variant of toon.gdshader (Danny's realism decree): identical uniforms
// and features — vertex-color albedo, fresnel rim, sky fill, world noise —
// but with soft wrapped diffuse instead of hard cel banding. Terrain, rocks,
// and large natural surfaces use this so SDFGI/SSAO light them naturally;
// characters keep the true toon shader so they still pop.

group_uniforms surface;
uniform bool use_srgb_vertex = true;
uniform float albedo_boost : hint_range(0.5, 1.5) = 1.0;
// Multiplies the vertex color. Left white, vertex COLOR drives the look
// (terrain, grass, trees). Set to a color for meshes with no vertex colors
// (the character capsule) so one shader serves both.
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rim_width : hint_range(0.0, 1.0) = 0.72;

group_uniforms fill;
uniform vec4 shadow_fill : source_color = vec4(0.55, 0.68, 0.92, 1.0);
uniform float fill_amount : hint_range(0.0, 0.6) = 0.14;

group_uniforms detail;
// World-space value noise multiplied into albedo. Zero for props; the
// terrain sets ~0.1 so big smooth surfaces stop reading as flat putty and
// pick up the mottled, hand-painted ground variation BOTW fields have.
uniform float noise_amount : hint_range(0.0, 0.3) = 0.0;
uniform float noise_scale : hint_range(0.05, 4.0) = 0.8;

varying vec3 v_col;
varying vec3 v_wpos;

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

void vertex() {
	// COLOR is authored as display (sRGB) values; linearize so saturation
	// survives the renderer's color management instead of washing pale.
	v_col = use_srgb_vertex ? pow(COLOR.rgb, vec3(2.2)) : COLOR.rgb;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = v_col * albedo_tint.rgb * albedo_boost;
	if (noise_amount > 0.001) {
		float n = vnoise(v_wpos.xz * noise_scale) * 0.6
				+ vnoise(v_wpos.xz * noise_scale * 4.7) * 0.4;
		ALBEDO *= 1.0 + (n - 0.5) * 2.0 * noise_amount;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	// Sky-colored fill added as flat emission lifts shadowed faces toward the
	// ambient hue — the trick that makes toon shadows look painted, not dead.
	// A small ambient floor keeps deep meadow colors chromatic in long shadows.
	EMISSION += shadow_fill.rgb * fill_amount * (ALBEDO * 0.78 + vec3(0.055));
	// Fresnel rim: bright where the surface turns away from the camera.
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(rim_width, 1.0, fres) * rim_amount;
	EMISSION += rim_color.rgb * rim;
}
