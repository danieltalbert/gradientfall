extends SceneTree
## Headless walkability audit for the climbable Gradient Peaks. Samples the
## exact height field the mesh and collision are built from and reports the
## steepest grade along each authored route and across each room pad, so a
## session can PROVE the routes clear Kern's 45° floor limit without a
## hands-on playthrough. Run:
##   godot --headless --script res://src/dev/peaks_audit.gd
## Dev tool only; never part of the shipped game.

const WALK_LIMIT_DEG: float = 45.0   # CharacterBody3D default floor_max_angle
const TARGET_DEG: float = 40.0       # design margin under the hard limit


func _initialize() -> void:
	var terrain: MeadowTerrain = MeadowTerrain.new()
	var peaks: GradientPeaks = GradientPeaks.new()
	peaks._terrain = terrain
	peaks._configure_noise()
	peaks._configure_channels()

	var all_ok: bool = true
	print("=== Gradient Peaks walkability audit ===")
	for channel_index in peaks._channels.size():
		var channel: Dictionary = peaks._channels[channel_index]
		var label: String = "valley route" if channel_index == 0 else "saddle ramp"
		var worst: float = 0.0
		var worst_at: Vector2 = Vector2.ZERO
		var nodes: Array = channel["nodes"]
		for i in nodes.size() - 1:
			var a: Vector3 = nodes[i]
			var b: Vector3 = nodes[i + 1]
			var length: float = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))
			var steps: int = maxi(int(length / 2.0), 1)
			for step in steps + 1:
				var t: float = float(step) / float(steps)
				var x: float = lerpf(a.x, b.x, t)
				var z: float = lerpf(a.y, b.y, t)
				var grade: float = _slope_deg(peaks, x, z)
				if grade > worst:
					worst = grade
					worst_at = Vector2(x, z)
		var verdict: String = _verdict(worst)
		all_ok = all_ok and worst < WALK_LIMIT_DEG
		print("%-14s worst grade %5.1f deg at (%.0f, %.0f)  %s" % [
			label, worst, worst_at.x, worst_at.y, verdict,
		])

	# Room interiors only (inner 40% of each pad radius): the rims are allowed
	# to be alpine cliff edges, and samples inside a trail's carve corridor are
	# skipped — a switchback cutting through a room owns that strip (its own
	# centreline is audited above; its embankment sides are intended cliffs).
	for i in peaks._pads.size():
		var pad: Vector4 = peaks._pads[i]
		var worst_pad: float = 0.0
		for sample in 60:
			var angle: float = TAU * float(sample) / 60.0
			var reach: float = pad.z * 0.4 * (0.3 + 0.7 * float(sample % 3) / 2.0)
			var px: float = pad.x + cos(angle) * reach
			var pz: float = pad.y + sin(angle) * reach
			var on_trail: bool = false
			for channel in peaks._channels:
				if peaks._channel_sample(Vector2(px, pz), channel)["mask"] > 0.02:
					on_trail = true
					break
			if on_trail:
				continue
			worst_pad = maxf(worst_pad, _slope_deg(peaks, px, pz))
		all_ok = all_ok and worst_pad < WALK_LIMIT_DEG
		print("pad %d (%.0f,%.0f) r%.0f  interior worst %5.1f deg  %s" % [
			i, pad.x, pad.y, pad.z, worst_pad, _verdict(worst_pad),
		])

	# Seam continuity: the peaks' near edge must sit just under the meadow edge
	# everywhere the two meet — a positive gap means a visible/catching ledge.
	var worst_gap: float = 0.0
	var x_check: float = -235.0
	while x_check <= 235.0:
		var meadow_h: float = terrain.get_height(x_check, GradientPeaks.NEAR_Z + 1.0)
		var peaks_h: float = peaks.get_height(x_check, GradientPeaks.NEAR_Z)
		worst_gap = maxf(worst_gap, absf(meadow_h - peaks_h))
		x_check += 5.0
	print("seam: worst meadow/peaks offset %.2f m (tuck target %.2f)  %s" % [
		worst_gap, GradientPeaks.SEAM_TUCK,
		"OK" if worst_gap < 0.5 else "GAP TOO LARGE",
	])
	all_ok = all_ok and worst_gap < 0.5

	print("=== AUDIT %s ===" % ("PASS" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)


func _slope_deg(peaks: GradientPeaks, x: float, z: float) -> float:
	var eps: float = 1.0
	var dx: float = (peaks.get_height(x + eps, z) - peaks.get_height(x - eps, z)) / (2.0 * eps)
	var dz: float = (peaks.get_height(x, z + eps) - peaks.get_height(x, z - eps)) / (2.0 * eps)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


func _verdict(worst: float) -> String:
	if worst < TARGET_DEG:
		return "OK"
	if worst < WALK_LIMIT_DEG:
		return "OK (inside margin)"
	return "TOO STEEP"
