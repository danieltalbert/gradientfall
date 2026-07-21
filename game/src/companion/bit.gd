class_name Bit
extends Node3D
## Bit — Kern's fairy-light companion (Phase 1 milestone 5).
##
## Three jobs, straight off the roadmap:
##   * FOLLOW — a framerate-independent hover that trails Kern's shoulder, bobs
##     and slow-orbits when he's still, snaps closer when he sprints away, and
##     (canon) shies UP and inward over deep water, which Bit is afraid of.
##   * LOOK-AT NAMING — Bit scans BitLandmark nodes; the first time Kern wanders
##     near one, Bit turns to face it, darts a little toward it, and eagerly
##     names it. ("names things eagerly", WORLDBOOK Part IV.)
##   * HINT LINES — a small in-voice barks system shown on a floating Label3D
##     and broadcast on EventBus.bit_spoke for the future dialogue UI. Lines
##     never overlap: they queue, and naming/greetings/water preempt idle chat.
##
## Visuals are code-built (no imported assets): an unshaded glowing core, an
## additive halo, two fluttering wings, and a soft omni light so Bit genuinely
## lights the ground at night. GDD §10 visible surface — flagged "unseen" until
## a live Godot session lays eyes on it.

# --- Follow feel ---
const HOVER_HEIGHT: float = 1.78
const SIDE_OFFSET: float = 0.85     # to the left of travel
const LEAD_OFFSET: float = 0.35     # a touch ahead, like a scout
const RESPONSE: float = 6.0         # exp-smoothing rate, normal
const RESPONSE_FAR: float = 12.0    # snappier when catching up
const FAR_DIST: float = 4.5
const BOB_SPEED: float = 2.3
const BOB_AMPLITUDE: float = 0.09
const IDLE_ORBIT_SPEED: float = 0.9
const IDLE_ORBIT_RADIUS: float = 0.55
const FACE_SPEED: float = 7.0
const MOVING_SPEED_SQ: float = 0.36  # (0.6 m/s)^2 counts as "moving"

# --- Water fear (canon) ---
const WATER_LIFT: float = 1.1
const WATER_BARK_CD: float = 8.0

# --- Naming ---
const SCAN_INTERVAL: float = 0.4
const NAME_COOLDOWN: float = 3.5     # beat between namings
const LOOK_HOLD: float = 2.2         # how long Bit keeps facing a named place
const DART_DISTANCE: float = 0.7
const DART_DECAY: float = 6.0

# --- Chatter ---
const IDLE_MIN: float = 13.0
const IDLE_MAX: float = 23.0
const ITEM_BARK_CD: float = 20.0
const SPEAK_MIN: float = 2.2
const SPEAK_PER_CHAR: float = 0.045
const FADE_OUT_TIME: float = 0.45

# Priorities: idle chat is disposable; the rest preempts it.
const PRIO_IDLE: int = 0
const PRIO_REACT: int = 1
const PRIO_URGENT: int = 2  # naming, greeting, water

var _player: CharacterBody3D
var _terrain: Node
var _water_level: float = 0.0

var _bob: float = 0.0
var _orbit: float = 0.0
var _flutter_phase: float = 0.0
var _dart_offset: Vector3 = Vector3.ZERO
var _look_point: Vector3 = Vector3.ZERO
var _look_left: float = 0.0
var _scan_left: float = 0.0
var _name_cd: float = 0.0
var _idle_left: float = 8.0
var _water_bark_cd: float = 0.0
var _item_bark_cd: float = 0.0
var _greeted: bool = false
var _last_region: String = ""
var _channeling: bool = false

# Speech
var _label: Label3D
var _wings: Array[Node3D] = []
var _speaking: bool = false
var _speak_left: float = 0.0
var _fading_out: bool = false
var _current_text: String = ""
var _queue: Array[Dictionary] = []
var _label_tween: Tween


func _ready() -> void:
	_build_visual()
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.region_entered.connect(_on_region_entered)
	EventBus.quiz_answered.connect(_on_quiz_answered)
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.knowledge_channel_started.connect(_on_channel_started)
	EventBus.knowledge_channel_ended.connect(_on_channel_ended)


## Called by the world builder once Kern and the terrain exist.
func setup(player: CharacterBody3D, terrain: Node) -> void:
	_player = player
	_terrain = terrain
	var wl: Variant = _terrain.get("water_level") if _terrain != null else null
	if wl != null:
		_water_level = float(wl)
	if _player != null:
		global_position = _player.global_position + Vector3(-SIDE_OFFSET, HOVER_HEIGHT, 0.0)
		if not _greeted:
			_greeted = true
			_say(BitLines.any(BitLines.GREETING), PRIO_URGENT, "greeting")


func _process(delta: float) -> void:
	_flutter(delta)
	_tick_speech(delta)
	if _player == null:
		return
	_follow(delta)
	_tick_scan(delta)
	_tick_idle(delta)
	_name_cd = maxf(0.0, _name_cd - delta)
	_water_bark_cd = maxf(0.0, _water_bark_cd - delta)
	_item_bark_cd = maxf(0.0, _item_bark_cd - delta)


# --- Follow ------------------------------------------------------------------

func _follow(delta: float) -> void:
	if _channeling:
		# Milestone 7: Bit darts in over Kern's head to combine power. The
		# world is in channel slow-mo, so undo Engine.time_scale on the lerp —
		# Bit visibly flies IN while everything else crawls.
		var over: Vector3 = _player.global_position + Vector3(0.0, HOVER_HEIGHT + 0.55, 0.0)
		var real_delta: float = delta / maxf(Engine.time_scale, 0.05)
		var ct: float = 1.0 - exp(-RESPONSE_FAR * real_delta)
		global_position = global_position.lerp(over, ct)
		_face(_player.global_position + Vector3(0.0, HOVER_HEIGHT * 0.6, 0.0), real_delta)
		return
	var anchor: Vector3 = _player.global_position + Vector3(0.0, HOVER_HEIGHT, 0.0)
	var planar: Vector2 = Vector2(_player.velocity.x, _player.velocity.z)
	var side: Vector3
	if planar.length_squared() > MOVING_SPEED_SQ:
		var fdir: Vector3 = Vector3(planar.x, 0.0, planar.y).normalized()
		var left: Vector3 = Vector3(fdir.z, 0.0, -fdir.x)
		side = left * SIDE_OFFSET + fdir * LEAD_OFFSET
	else:
		_orbit += delta * IDLE_ORBIT_SPEED
		side = Vector3(cos(_orbit), 0.0, sin(_orbit)) * IDLE_ORBIT_RADIUS

	var target: Vector3 = anchor + side
	_bob += delta * BOB_SPEED
	target.y += sin(_bob) * BOB_AMPLITUDE

	var scared: bool = _is_over_deep_water(target)
	if scared:
		target = target.lerp(anchor, 0.5)
		target.y += WATER_LIFT
		_maybe_water_bark()

	var response: float = RESPONSE_FAR if global_position.distance_to(target) > FAR_DIST else RESPONSE
	var t: float = 1.0 - exp(-response * delta)
	global_position = global_position.lerp(target, t)

	# Dart lunge from a fresh naming, easing back as the follow catches up.
	global_position += _dart_offset
	_dart_offset = _dart_offset.lerp(Vector3.ZERO, 1.0 - exp(-DART_DECAY * delta))

	# Facing: hold on a named place, else look the way we're travelling.
	var face_point: Vector3
	if _look_left > 0.0:
		_look_left -= delta
		face_point = _look_point
	elif planar.length_squared() > MOVING_SPEED_SQ:
		face_point = global_position + Vector3(planar.x, 0.0, planar.y)
	else:
		face_point = _player.global_position + Vector3(0.0, HOVER_HEIGHT * 0.6, 0.0)
	_face(face_point, delta)


func _face(point: Vector3, delta: float) -> void:
	var to: Vector3 = point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var desired_yaw: float = atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, FACE_SPEED * delta))


func _is_over_deep_water(p: Vector3) -> bool:
	if _terrain != null and _terrain.has_method("is_deep_water"):
		return bool(_terrain.is_deep_water(p.x, p.z))
	return false


func _maybe_water_bark() -> void:
	if _water_bark_cd > 0.0 or _speaking:
		return
	_water_bark_cd = WATER_BARK_CD
	_say(BitLines.any(BitLines.WATER_FEAR), PRIO_URGENT, "water")


# --- Look-at naming ----------------------------------------------------------

func _tick_scan(delta: float) -> void:
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_INTERVAL
	if _name_cd > 0.0:
		return
	var best: BitLandmark = null
	var best_d: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"bit_landmark"):
		var lm: BitLandmark = node as BitLandmark
		if lm == null or GameState.has_flag(lm.named_flag()):
			continue
		var d: float = _player.global_position.distance_to(lm.global_position)
		if d <= lm.notice_radius and d < best_d:
			best_d = d
			best = lm
	if best != null:
		_name_landmark(best)


func _name_landmark(lm: BitLandmark) -> void:
	GameState.set_flag(lm.named_flag(), true)
	_look_point = lm.global_position
	_look_left = LOOK_HOLD
	_name_cd = NAME_COOLDOWN
	var toward: Vector3 = lm.global_position - global_position
	toward.y = 0.0
	if toward.length() > 0.001:
		_dart_offset = toward.normalized() * DART_DISTANCE
	_say(lm.pick_line(), PRIO_URGENT, "naming")
	EventBus.landmark_named.emit(lm.landmark_id, lm.display_name)


# --- Idle chatter & reactions ------------------------------------------------

func _tick_idle(delta: float) -> void:
	_idle_left -= delta
	if _idle_left > 0.0:
		return
	_idle_left = randf_range(IDLE_MIN, IDLE_MAX)
	if _speaking or _name_cd > 0.0:
		return
	var pool: Array[String] = BitLines.HINT if randf() < 0.34 else BitLines.IDLE
	_say(BitLines.any(pool), PRIO_IDLE, "idle")


func _on_player_spawned(player: Node3D) -> void:
	_player = player as CharacterBody3D
	if _player != null and not _greeted:
		_greeted = true
		_say(BitLines.any(BitLines.GREETING), PRIO_URGENT, "greeting")


func _on_region_entered(region_id: String) -> void:
	if region_id == _last_region:
		return
	_last_region = region_id
	if region_id == "datasedge_meadows":
		_say("Datasedge Meadows — golden as ever. Home base, Kern.", PRIO_REACT, "region")


func _on_quiz_answered(_quiz_id: String, correct: bool) -> void:
	var pool: Array[String] = BitLines.QUIZ_CORRECT if correct else BitLines.QUIZ_WRONG
	_say(BitLines.any(pool), PRIO_REACT, "quiz")


func _on_channel_started() -> void:
	_channeling = true
	_say(BitLines.any(BitLines.CHANNEL_START), PRIO_URGENT, "channel")


func _on_channel_ended(completed: bool) -> void:
	_channeling = false
	var pool: Array[String] = BitLines.CHANNEL_SUCCESS if completed else BitLines.CHANNEL_FIZZLE
	_say(BitLines.any(pool), PRIO_URGENT, "channel")


func _on_item_acquired(_item_id: String, _count: int) -> void:
	if _item_bark_cd > 0.0 or _speaking or randf() > 0.5:
		return
	_item_bark_cd = ITEM_BARK_CD
	_say(BitLines.any(BitLines.ITEM_PICKUP), PRIO_REACT, "item")


# --- Speech ------------------------------------------------------------------

func _say(text: String, prio: int, kind: String) -> void:
	if text.is_empty():
		return
	if prio >= PRIO_URGENT:
		# Urgent lines jump the queue, keeping only other urgent lines behind.
		var kept: Array[Dictionary] = []
		for e: Dictionary in _queue:
			if int(e["prio"]) >= PRIO_URGENT:
				kept.append(e)
		_queue = kept
		_start_line(text, kind)
		return
	if _speaking:
		if _queue.size() < 2 and _current_text != text:
			_queue.append({"text": text, "kind": kind, "prio": prio})
	else:
		_start_line(text, kind)


func _start_line(text: String, kind: String) -> void:
	_current_text = text
	_speaking = true
	_fading_out = false
	_speak_left = SPEAK_MIN + float(text.length()) * SPEAK_PER_CHAR
	if _label != null:
		_label.text = text
		_fade_label(1.0, 0.18)
	print("[Bit] ", text)
	EventBus.bit_spoke.emit(text, kind)


func _tick_speech(delta: float) -> void:
	if not _speaking:
		if not _queue.is_empty():
			var e: Dictionary = _queue.pop_front()
			_start_line(String(e["text"]), String(e["kind"]))
		return
	_speak_left -= delta
	if _speak_left <= FADE_OUT_TIME and not _fading_out:
		_fading_out = true
		_fade_label(0.0, FADE_OUT_TIME)
	if _speak_left <= 0.0:
		_speaking = false
		_fading_out = false
		_current_text = ""
		if _label != null:
			_label.text = ""


func _fade_label(to_alpha: float, time: float) -> void:
	if _label == null:
		return
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()
	_label_tween = create_tween()
	_label_tween.tween_property(_label, "modulate:a", to_alpha, time)


# --- Visual build (code-only) ------------------------------------------------

func _flutter(delta: float) -> void:
	_flutter_phase += delta * 26.0
	var beat: float = sin(_flutter_phase) * 0.6 + 0.4
	if _wings.size() == 2:
		_wings[0].rotation.y = 0.6 + beat
		_wings[1].rotation.y = -0.6 - beat


func _build_visual() -> void:
	var core: MeshInstance3D = MeshInstance3D.new()
	var core_mesh: SphereMesh = SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.24
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	core.mesh = core_mesh
	core.material_override = _emissive(Color(1.0, 0.86, 0.42), Color(1.0, 0.7, 0.22), 6.5, 1.0, false)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var halo: MeshInstance3D = MeshInstance3D.new()
	var halo_mesh: SphereMesh = SphereMesh.new()
	halo_mesh.radius = 0.30
	halo_mesh.height = 0.60
	halo_mesh.radial_segments = 12
	halo_mesh.rings = 6
	halo.mesh = halo_mesh
	halo.material_override = _emissive(Color(1.0, 0.82, 0.4), Color(1.0, 0.66, 0.2), 2.4, 0.28, true)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	for sign_x: int in [-1, 1]:
		var wing: Node3D = Node3D.new()
		wing.position = Vector3(0.1 * sign_x, 0.03, 0.0)
		add_child(wing)
		var blade: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(0.26, 0.16)
		blade.mesh = quad
		blade.position = Vector3(0.13 * sign_x, 0.0, 0.0)
		blade.material_override = _emissive(Color(0.7, 0.9, 1.0), Color(0.55, 0.8, 1.0), 1.6, 0.22, true)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing.add_child(blade)
		_wings.append(wing)

	var glow: OmniLight3D = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.78, 0.4)
	glow.light_energy = 1.4
	glow.omni_range = 6.5
	glow.shadow_enabled = false
	add_child(glow)

	_label = Label3D.new()
	_label.text = ""
	_label.pixel_size = 0.0032
	_label.font_size = 48
	_label.outline_size = 14
	_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_label.outline_modulate = Color(0.05, 0.06, 0.08, 0.85)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.double_sided = true
	_label.position = Vector3(0.0, 0.5, 0.0)
	_label.width = 520.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)


func _emissive(albedo: Color, emit: Color, energy: float, alpha: float, additive: bool) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(albedo.r, albedo.g, albedo.b, alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = emit
	mat.emission_energy_multiplier = energy
	if additive or alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
