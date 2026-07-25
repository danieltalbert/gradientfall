class_name KnowledgeQuiz
extends Node
## The in-combat quiz prompt that charges Kern's special — Phase 1 milestone 7.
##
## Combat v1 built the meter and the shard-nova that spends it; this is the
## SOURCE the meter was waiting for. GDD §9: "answering an ML question (drawn
## from the quiz bank, scaled to campaign progress) charges special abilities".
##
## The loop, and why it is shaped this way:
##   * A question is only ever offered mid-fight, a few seconds in — the charge
##     is a combat resource, not a menu chore, and never interrupts exploring.
##   * The world does NOT pause and time does NOT slow. Fights happen in-world,
##     in place (GDD §9), so the card lives at the bottom of the screen while
##     the monster keeps coming. (Slowing time here would also fight Combat v1's
##     hitstop over Engine.time_scale — one owner for that knob, and it is the
##     sword.)
##   * Taking a hit while the card is up breaks concentration and dismisses it,
##     no penalty beyond the lost chance. That is the whole risk/reward: make
##     space in the fight — dodge out, put a wall between you — then answer.
##   * A wrong answer costs nothing but the charge you didn't earn, and the card
##     always shows the right answer with its explanation. This is a teaching
##     game; being wrong is a lesson, not a punishment (GDD tone, all-ages).
##
## Everything it announces goes out on EventBus.quiz_answered — PlayerCombat
## turns that into focus, Bit reacts to it in her own voice, and nothing here
## knows about either of them.
##
## Owns its card (a view, not a peer system); question choice lives in QuizBank.
##
## GDD §10 visible surface: UNSEEN — built with no Godot in the environment. A
## live session must fight, answer, and watch the meter before this ticks clean.

enum Phase { IDLE, ASKING, REVEAL }

## An enemy this close counts as "in a fight" (Enemy aggros at 14 m).
const ENGAGE_RADIUS: float = 18.0
const SCAN_INTERVAL: float = 0.35
## Blows landed either way keep the fight "hot" through a lull or a chase.
const COMBAT_MEMORY: float = 5.0
## Let the player actually start fighting before the first question.
const FIRST_OFFER_DELAY: float = 4.0

const COOLDOWN_CORRECT: float = 15.0
const COOLDOWN_WRONG: float = 9.0
const COOLDOWN_TIMEOUT: float = 8.0
const COOLDOWN_INTERRUPTED: float = 4.5
const COOLDOWN_EMPTY_BANK: float = 60.0

## Reading time scales with the question's rating: D1 gets 8 s, D5 gets 14 s.
const ANSWER_TIME_BASE: float = 8.0
const ANSWER_TIME_PER_DIFFICULTY: float = 1.5

## How long the verdict stays up. A right answer only needs the beat that says
## so; a wrong or missed one leaves the explanation long enough to actually read
## — that lesson is the whole reason the bank has an `explanation` field.
const REVEAL_TIME_CORRECT: float = 3.0
const REVEAL_TIME_BASE: float = 2.8
const REVEAL_TIME_PER_CHAR: float = 0.02
const REVEAL_TIME_MAX: float = 6.5

const REWARD_SHARDS: int = 18
const REWARD_COLOR: Color = Color(1.0, 0.85, 0.40)

const CHOICE_ACTIONS: Array[StringName] = [
	&"quiz_choice_1", &"quiz_choice_2", &"quiz_choice_3", &"quiz_choice_4",
]

var enabled: bool = true

var _bank: QuizBank = QuizBank.new()
var _card: QuizCard

var _phase: int = Phase.IDLE
var _phase_time: float = 0.0
var _answer_time: float = ANSWER_TIME_BASE
var _reveal_time: float = REVEAL_TIME_CORRECT
var _current: Dictionary = {}

var _cooldown: float = 0.0
var _heat: float = 0.0
var _engaged_time: float = 0.0
var _enemy_near: bool = false
var _scan_left: float = 0.0

var _charge: float = 0.0
var _downed: bool = false
var _player: Node3D


func _ready() -> void:
	_card = QuizCard.new()
	_card.name = "QuizCard"
	add_child(_card)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_reformed.connect(_on_player_reformed)
	EventBus.knowledge_charge_changed.connect(_on_charge_changed)
	EventBus.enemy_hit.connect(_on_enemy_hit)
	print("Knowledge charge v1 online: %d question(s) reachable in '%s' (up to difficulty %d)." % [
		_bank.eligible_count(GameState.current_region),
		GameState.current_region,
		QuizBank.max_difficulty(GameState.current_region),
	])


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_heat = maxf(0.0, _heat - delta)
	_track_engagement(delta)
	if InputMap.has_action(&"debug_quiz") and Input.is_action_just_pressed(&"debug_quiz"):
		offer_now()  # dev-only: a question on demand, fight or no fight
	match _phase:
		Phase.IDLE:
			if enabled and _should_offer():
				offer_now()
		Phase.ASKING:
			_tick_asking(delta)
		Phase.REVEAL:
			_phase_time += delta
			if _phase_time >= _reveal_time:
				_card.dismiss()
				_phase = Phase.IDLE


## True while a question is on screen — other systems may want to know later
## (a dialogue UI, for one, should not open on top of it).
func is_asking() -> bool:
	return _phase == Phase.ASKING


## The question currently on screen, or an empty Dictionary. Read-only copy.
func current_question() -> Dictionary:
	return _current.duplicate(true) if _phase == Phase.ASKING else {}


## Put a question up right now. Returns false if the bank had nothing to ask.
func offer_now() -> bool:
	if _phase != Phase.IDLE:
		return false
	var entry: Dictionary = _bank.draw(GameState.current_region)
	if entry.is_empty():
		push_warning("KnowledgeQuiz: no approved quiz is reachable for region '%s' at difficulty <= %d."
			% [GameState.current_region, QuizBank.max_difficulty(GameState.current_region)])
		_cooldown = COOLDOWN_EMPTY_BANK
		return false
	_current = entry
	_answer_time = ANSWER_TIME_BASE \
		+ ANSWER_TIME_PER_DIFFICULTY * float(maxi(1, int(entry.get("difficulty", 1))) - 1)
	_phase = Phase.ASKING
	_phase_time = 0.0
	_card.ask(entry)
	return true


# --- Offer conditions --------------------------------------------------------

func _should_offer() -> bool:
	if _downed or _cooldown > 0.0:
		return false
	if _charge >= 1.0:
		return false  # meter's full — go spend it, that's the lesson right now
	return _engaged_time >= FIRST_OFFER_DELAY


func _track_engagement(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_INTERVAL
		_enemy_near = _is_enemy_near()
	if _enemy_near or _heat > 0.0:
		_engaged_time += delta
	else:
		_engaged_time = 0.0


func _is_enemy_near() -> bool:
	var player: Node3D = _player_node()
	if player == null:
		return false
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Node3D = node as Node3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if enemy.has_method(&"is_alive") and not enemy.call(&"is_alive"):
			continue
		# Horizontal range, like Enemy's own aggro/leash: a monster on the slope
		# above you is still very much in the fight.
		var to: Vector3 = enemy.global_position - player.global_position
		if Vector2(to.x, to.z).length() <= ENGAGE_RADIUS:
			return true
	return false


func _player_node() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player


# --- The question itself -----------------------------------------------------

func _tick_asking(delta: float) -> void:
	_phase_time += delta
	_card.set_time_left(1.0 - clampf(_phase_time / _answer_time, 0.0, 1.0))
	var picked: int = _read_choice()
	if picked >= 0:
		_answer(picked)
		return
	if _phase_time >= _answer_time:
		_card.time_out()
		_finish(COOLDOWN_TIMEOUT, _reveal_seconds(false))


func _read_choice() -> int:
	for i in CHOICE_ACTIONS.size():
		if InputMap.has_action(CHOICE_ACTIONS[i]) and Input.is_action_just_pressed(CHOICE_ACTIONS[i]):
			return i
	return -1


func _answer(picked: int) -> void:
	var correct: bool = picked == int(_current.get("answer_index", -1))
	var quiz_id: String = str(_current.get("id", ""))
	if correct:
		_reward_burst()
	# Emit BEFORE the reveal: PlayerCombat adds the charge synchronously, so by
	# the time the card is told, it can honestly say whether focus just filled.
	EventBus.quiz_answered.emit(quiz_id, correct)
	_card.reveal(picked, correct, _charge >= 1.0)
	_finish(COOLDOWN_CORRECT if correct else COOLDOWN_WRONG, _reveal_seconds(correct))


func _finish(cooldown: float, reveal_seconds: float) -> void:
	_phase = Phase.REVEAL
	_phase_time = 0.0
	_reveal_time = reveal_seconds
	_cooldown = maxf(cooldown, reveal_seconds)  # never re-ask over a live verdict


## A right answer needs a beat; a wrong one needs however long its explanation
## takes to read.
func _reveal_seconds(correct: bool) -> float:
	if correct:
		return REVEAL_TIME_CORRECT
	var length: int = str(_current.get("explanation", "")).length()
	return minf(REVEAL_TIME_MAX, REVEAL_TIME_BASE + REVEAL_TIME_PER_CHAR * float(length))


## Kern's own answer, shown in-world: a small burst of the same data-shards
## everything in this game comes apart into, rising gold instead of scattering.
func _reward_burst() -> void:
	var player: Node3D = _player_node()
	if player == null:
		return
	DamageShards.burst(get_tree().current_scene,
		player.global_position + Vector3(0.0, 1.05, 0.0), REWARD_COLOR,
		REWARD_SHARDS, 2.6, 3.0, 0.85)


# --- EventBus reactions ------------------------------------------------------

func _on_player_hit(_amount: float) -> void:
	_heat = COMBAT_MEMORY
	if _phase == Phase.ASKING:
		# Concentration broken. No verdict, no penalty — just the lost chance.
		_card.interrupt()
		_phase = Phase.IDLE
		_cooldown = COOLDOWN_INTERRUPTED


func _on_enemy_hit(_monster_id: String, _remaining_hearts: float) -> void:
	_heat = COMBAT_MEMORY


func _on_player_died() -> void:
	_downed = true
	if _phase != Phase.IDLE:
		_card.interrupt()
		_phase = Phase.IDLE
		_cooldown = COOLDOWN_INTERRUPTED


func _on_player_reformed() -> void:
	_downed = false
	_engaged_time = 0.0
	_cooldown = maxf(_cooldown, FIRST_OFFER_DELAY)


func _on_charge_changed(fraction: float) -> void:
	_charge = fraction
