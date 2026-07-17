shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Reusable cel-shading (GDD §10: cel/toon shading with rim light is the
// single biggest visual lever). Godot's built-in diffuse_toon gives the
// hard banded terminator; on top we add a fresnel rim so forms pop off the
// background, and a soft sky-tinted fill in shadow so the dark side reads as
// shape rather than a black hole. Albedo comes from per-vertex COLOR — the
// whole world is generated in code with no textures.

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

varying vec3 v_col;

void vertex() {
	// COLOR is authored as display (sRGB) values; linearize so saturation
	// survives the renderer's color management instead of washing pale.
	v_col = use_srgb_vertex ? pow(COLOR.rgb, vec3(2.2)) : COLOR.rgb;
}

void fragment() {
	ALBEDO = v_col * albedo_tint.rgb * albedo_boost;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	// Sky-colored fill added as flat emission lifts shadowed faces toward the
	// ambient hue — the trick that makes toon shadows look painted, not dead.
	EMISSION += shadow_fill.rgb * fill_amount * ALBEDO;
	// Fresnel rim: bright where the surface turns away from the camera.
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(rim_width, 1.0, fres) * rim_amount;
	EMISSION += rim_color.rgb * rim;
}
