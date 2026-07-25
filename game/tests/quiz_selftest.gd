extends Node
## Knowledge charge v1 — headless self-test (Phase 1 milestone 7).
##
##     godot --headless --path game --fixed-fps 60 res://tests/quiz_selftest.tscn
##
## Exits 0 on PASS, 1 on FAIL, and prints a line per check, so a session with no
## eyes on the game can still prove the loop works: gate → draw → offer → answer
## → charge → special, plus the wrong / timed-out / interrupted branches.
## `--fixed-fps 60` matters: the timings are counted in frames.
##
## It drives the REAL scenes and autoloads (player.tscn, ContentDB's approved
## quiz bank, the live EventBus), so it fails when the wiring rots — not when a
## mock drifts. Nothing here is imported by the game itself; deleting this file
## would cost the project its only regression net for this system.

var _answers: Array = []
var _charges: Array = []
var _draws: int = 0
var _fails: int = 0
var _quiz: KnowledgeQuiz
var _player: Node3D


func _ready() -> void:
	EventBus.quiz_answered.connect(_on_quiz_answered)
	EventBus.knowledge_charge_changed.connect(_on_charge)
	await _run()
	print("\n==== SELFTEST %s (%d failure(s)) ====" % ["FAIL" if _fails > 0 else "PASS", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _on_quiz_answered(id: String, correct: bool) -> void:
	_answers.append([id, correct])


func _on_charge(f: float) -> void:
	_charges.append(f)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("[%s] %s%s" % ["ok " if ok else "FAIL", label, ("  — " + detail) if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	print("\n--- A. QuizBank gating -------------------------------------------")
	var bank: QuizBank = QuizBank.new()
	GameState.flags.clear()
	_check("no shrines -> cap 2", QuizBank.max_difficulty("datasedge_meadows") == 2,
		"cap=%d" % QuizBank.max_difficulty("datasedge_meadows"))
	_check("no shrines -> 17 reachable", bank.eligible_count("datasedge_meadows") == 17,
		"n=%d" % bank.eligible_count("datasedge_meadows"))
	for i in 3:
		GameState.set_flag(QuizBank.SHRINE_FLAGS[i], true)
	_check("3 shrines -> cap 3", QuizBank.max_difficulty("datasedge_meadows") == 3)
	for i in 6:
		GameState.set_flag(QuizBank.SHRINE_FLAGS[i], true)
	_check("6 shrines -> cap 4", QuizBank.max_difficulty("datasedge_meadows") == 4)
	_check("6 shrines + citadel -> cap 5", QuizBank.max_difficulty("corpus_citadel") == 5)
	for i in 9:
		GameState.set_flag(QuizBank.SHRINE_FLAGS[i], true)
	_check("9 shrines -> cap 5 anywhere", QuizBank.max_difficulty("datasedge_meadows") == 5)
	_check("9 shrines -> whole bank (41)", bank.eligible_count("datasedge_meadows") == 41,
		"n=%d" % bank.eligible_count("datasedge_meadows"))
	GameState.flags.clear()

	print("\n--- B. QuizBank draw rotation ------------------------------------")
	var seen: Dictionary = {}
	var last: String = ""
	var repeats: int = 0
	var bad: int = 0
	var topics: Dictionary = {}
	for i in 200:
		var e: Dictionary = bank.draw("datasedge_meadows")
		if e.is_empty():
			bad += 1
			continue
		var id: String = str(e["id"])
		if id == last:
			repeats += 1
		last = id
		seen[id] = int(seen.get(id, 0)) + 1
		topics[str(e.get("topic", "?"))] = true
		if int(e.get("difficulty", 9)) > 2:
			bad += 1
	_check("200 draws all returned a question", bad == 0, "bad=%d" % bad)
	_check("never the same question twice running", repeats == 0, "repeats=%d" % repeats)
	_check("rotation covers the whole eligible pool", seen.size() == 17, "distinct=%d" % seen.size())
	var counts: Array = seen.values()
	counts.sort()
	_check("rotation is even (max-min <= 1)", int(counts[-1]) - int(counts[0]) <= 1,
		"min=%d max=%d" % [int(counts[0]), int(counts[-1])])
	_check("meadow leans on its topics", topics.has("ml_basics") and topics.has("data"),
		str(topics.keys()))

	print("\n--- C. empty-ish bank edge cases ---------------------------------")
	var solo: QuizBank = QuizBank.new()
	var first: Dictionary = solo.draw("datasedge_meadows")
	_check("draw works from a fresh bank", not first.is_empty())

	print("\n--- D. live wiring: player + director ----------------------------")
	_build_floor()
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	_player = player_scene.instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	await _frames(30)
	_check("player is in the 'player' group", _player.is_in_group(&"player"))
	_charges.clear()
	EventBus.quiz_answered.emit("quiz_ml_basics_001", true)  # a difficulty-1 record
	await _frames(2)
	_check("D1 correct answer -> 0.34 charge", _charges.size() > 0 and is_equal_approx(float(_charges[-1]), 0.34),
		str(_charges))
	var d5: String = _find_quiz_with_difficulty(5)
	_charges.clear()
	EventBus.quiz_answered.emit(d5, true)
	await _frames(2)
	_check("D5 correct answer -> +0.58 charge", _charges.size() > 0 and is_equal_approx(float(_charges[-1]), 0.92),
		"%s -> %s" % [d5, str(_charges)])
	_charges.clear()
	EventBus.quiz_answered.emit("quiz_ml_basics_001", false)
	await _frames(2)
	_check("a wrong answer charges nothing", _charges.is_empty(), str(_charges))
	_charges.clear()
	EventBus.quiz_answered.emit("quiz_ml_basics_001", true)
	await _frames(2)
	_check("the meter clamps at full", _charges.size() > 0 and is_equal_approx(float(_charges[-1]), 1.0),
		str(_charges))
	# The whole point of the charge: spend it. Q fires the shard-nova.
	_charges.clear()
	Input.action_press(&"special")
	await _frames(3)
	Input.action_release(&"special")
	await _frames(3)
	_check("the special spends the whole meter",
		_charges.size() > 0 and is_equal_approx(float(_charges[-1]), 0.0), str(_charges))

	print("\n--- E. director: offer, answer, reveal ---------------------------")
	_quiz = KnowledgeQuiz.new()
	add_child(_quiz)
	var card: CanvasLayer = _quiz.get_node("QuizCard")
	(card.get_node("CardCanvas") as Control).draw.connect(_on_card_draw)
	_check("fallback font is available", ThemeDB.fallback_font != null)
	await _frames(30)
	_check("no question without a fight", not _quiz.is_asking())
	var dummy: Node3D = Node3D.new()
	dummy.add_to_group(&"enemy")
	add_child(dummy)
	dummy.global_position = _player.global_position + Vector3(5.0, 0.0, 0.0)
	await _frames(60)
	_check("still no question during the grace beat", not _quiz.is_asking())
	await _frames(260)
	_check("a fight offers a question", _quiz.is_asking())
	await _frames(4)
	_check("the card actually drew", _draws > 0, "draws=%d" % _draws)

	_answers.clear()
	_charges.clear()
	var asked: Dictionary = _current_entry()
	var right: int = int(asked.get("answer_index", 0))
	await _press_choice(right)
	_check("answering emits quiz_answered(correct)", _answers.size() == 1 and bool(_answers[0][1]),
		str(_answers))
	_check("answering charges the meter", _charges.size() == 1 and float(_charges[0]) > 0.0, str(_charges))
	_check("the card is no longer asking", not _quiz.is_asking())
	await _frames(6)
	_check("the reveal still draws", _draws > 0)

	print("\n--- F. wrong answer, timeout, interrupt --------------------------")
	_check("a second question follows", await _wait_asking(true, 60 * 30))
	_answers.clear()
	var entry2: Dictionary = _current_entry()
	var wrong: int = (int(entry2.get("answer_index", 0)) + 1) % 4
	await _press_choice(wrong)
	_check("a wrong pick emits correct=false", _answers.size() == 1 and not bool(_answers[0][1]),
		str(_answers))

	_check("a third question follows", await _wait_asking(true, 60 * 30))
	_answers.clear()
	_check("an unanswered question times out", await _wait_asking(false, 60 * 20))
	_check("a timeout is not scored as an answer", _answers.is_empty(), str(_answers))

	_check("a fourth question follows", await _wait_asking(true, 60 * 30))
	_answers.clear()
	EventBus.player_hit.emit(0.5)
	await _frames(3)
	_check("taking a hit breaks the question off", not _quiz.is_asking())
	_check("an interrupted question is not scored", _answers.is_empty(), str(_answers))

	print("\n--- G. full meter stops the questions ----------------------------")
	EventBus.knowledge_charge_changed.emit(1.0)
	await _frames(60 * 20)
	_check("no questions while focus is full", not _quiz.is_asking())


func _wait_asking(want: bool, max_frames: int) -> bool:
	for i in max_frames:
		if _quiz.is_asking() == want:
			return true
		await get_tree().process_frame
	return _quiz.is_asking() == want


func _build_floor() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)


func _on_card_draw() -> void:
	_draws += 1


func _current_entry() -> Dictionary:
	return _quiz.current_question()


func _press_choice(index: int) -> void:
	var action: StringName = KnowledgeQuiz.CHOICE_ACTIONS[index]
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _find_quiz_with_difficulty(d: int) -> String:
	for e: Dictionary in ContentDB.get_all("quizzes"):
		if int(e.get("difficulty", 0)) == d:
			return str(e["id"])
	return ""
