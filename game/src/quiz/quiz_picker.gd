class_name QuizPicker
extends RefCounted
## Selects questions from the approved ContentDB quiz bank for the knowledge
## channel — Phase 1 milestone 7.
##
## Difficulty gating is the WORLDBOOK Part III rule verbatim: D1–2 anywhere;
## D3 after Shrine 3; D4 after Shrine 6; D5 only in the Citadel / endgame.
## Shrines don't exist yet, so the gate reads the shrine flags they WILL set
## (`shrine_N_cleared`, N 1..9) and resolves to D1–2 across the whole
## vertical slice — it scales automatically as the campaign lands.
##
## Selection is a shuffle bag: no question repeats until every eligible
## question has been asked once, then the bag reshuffles.

var _bag: Array[Dictionary] = []
var _bag_limit: int = -1
var _last_id: String = ""


## The campaign-progress → max-difficulty function (WORLDBOOK Part III).
static func max_difficulty() -> int:
	if GameState.current_region == "corpus_citadel" or GameState.has_flag("endgame_unlocked"):
		return 5
	var shrines: int = 0
	for i: int in range(1, 10):
		if GameState.has_flag("shrine_%d_cleared" % i):
			shrines += 1
	if shrines >= 6:
		return 4
	if shrines >= 3:
		return 3
	return 2


## Next question at the allowed difficulty, or {} if the bank has none.
func next() -> Dictionary:
	var limit: int = max_difficulty()
	if _bag.is_empty() or _bag_limit != limit:
		_refill(limit)
	if _bag.is_empty():
		return {}
	var q: Dictionary = _bag.pop_back()
	# Don't let a fresh shuffle immediately repeat the last question asked.
	if str(q.get("id", "")) == _last_id and not _bag.is_empty():
		_bag.push_front(q)
		q = _bag.pop_back()
	_last_id = str(q.get("id", ""))
	return q


func _refill(limit: int) -> void:
	_bag_limit = limit
	_bag.clear()
	for quiz: Dictionary in ContentDB.get_all("quizzes"):
		if int(quiz.get("difficulty", 99)) <= limit:
			_bag.append(quiz)
	_bag.shuffle()
