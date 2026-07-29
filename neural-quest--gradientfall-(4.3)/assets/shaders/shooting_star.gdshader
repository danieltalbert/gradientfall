shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// One meteor streak. The quad's local X runs head -> tail; `life` (0..1)
// plays the whole event: streak grows, the head burns bright, then the tail
// dissipates. CelestialLayer positions/aims the quad and drives `life`.
uniform float life : hint_range(0.0, 1.0) = 0.0;
uniform vec4 streak_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Head sits at u=0. The visible streak window slides with life so the
	// meteor draws in, then burns out from the tail forward.
	float u = v_uv.x;
	float head_pos = smoothstep(0.0, 0.75, life);          // head travels 0 -> 1
	float tail_len = 0.30 * (1.0 - life * 0.55);           // tail tightens late
	float along = (head_pos - u) / max(tail_len, 0.03);    // 0 at head, 1 at tail end
	float streak = step(0.0, along) * exp(-along * 3.4) * step(u, head_pos);

	// Crisp core line with a soft vertical falloff.
	float across = 1.0 - smoothstep(0.0, 0.5, abs(v_uv.y - 0.5));
	across = pow(across, 2.6);

	// Bright head bead.
	float head = exp(-abs(u - head_pos) * 46.0) * across * 2.4;

	// Whole-event envelope: quick attack, smooth decay.
	float envelope = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.55, 1.0, life));

	float intensity = (streak * across + head) * envelope;
	ALBEDO = streak_color.rgb;
	EMISSION = streak_color.rgb * intensity * 3.2;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
