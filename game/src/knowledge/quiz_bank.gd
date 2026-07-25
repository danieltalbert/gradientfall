class_name QuizBank
extends RefCounted
## Chooses the question a knowledge charge is earned with — Phase 1 milestone 7.
##
## The bank itself is authored content: every entry comes from ContentDB's
## approved `quizzes` (schema-validated upstream, never invented here). This
## class is only the draw policy, kept apart from the in-combat director so the
## "which question" rules can be reasoned about — and later reused by the
## Citadel's quiz gauntlet and the Library trials — without dragging combat
## state along.
##
## Three rules shape a draw:
##   1. **Campaign gating** (WORLDBOOK Part III): D1–2 anywhere, D3 after three
##      Memory Shrines, D4 after six, D5 only at the endgame. A brand-new player
##      is never handed a question the game hasn't taught yet.
##   2. **Region affinity**: a region can prefer the topics it teaches (the
##      starter meadow leans on foundations and data) without ever hard-locking
##      the rest of the bank away.
##   3. **No nagging repeats**: questions already asked this session are held
##      back until the eligible pool runs dry, and the immediately previous
##      question never comes straight back.
##
## Entries are validated defensively on the way out: ContentDB is a plain JSON
## reader, so a malformed record must never reach the player as an unanswerable
## card.

## Memory Shrine flags in WORLDBOOK Part I order (shrine 1 → 9). The shrines
## themselves are a Phase 4 milestone; this is the canonical flag id each one
## will set on GameState, declared here so the gate below already works and the
## shrine milestone has a name to honour rather than invent.
const SHRINE_FLAGS: Array[String] = [
	"shrine_first_light",     # 1 · Datasedge Meadows
	"shrine_ledger",          # 2 · Parameter City
	"shrine_deep_roots",      # 3 · Latent Forest
	"shrine_second_voice",    # 4 · Frozen Cache
	"shrine_broken_scale",    # 5 · Tensor Desert
	"shrine_embers",          # 6 · Backprop Foundry
	"shrine_tide",            # 7 · Convolution Coast
	"shrine_summit",          # 8 · Gradient Peaks
	"shrine_first_question",  # 9 · Corpus Citadel exterior
]

const SHRINES_FOR_D3: int = 3
const SHRINES_FOR_D4: int = 6
const BASE_MAX_DIFFICULTY: int = 2
const TOP_DIFFICULTY: int = 5
const ENDGAME_REGION: String = "corpus_citadel"

## region id -> topics that region leans on. Absent (or empty) means "any
## topic"; the preference is a lean, never a lock — see PREFERRED_CHANCE.
const REGION_TOPICS: Dictionary = {
	"datasedge_meadows": ["ml_basics", "data"],
}
const PREFERRED_CHANCE: float = 0.75

const CHOICE_COUNT: int = 4

var _asked: Dictionary = {}   ## quiz id -> true, this session only
var _last_id: String = ""


## Returns an approved quiz entry for `region`, or an empty Dictionary when the
## bank has nothing eligible (no approved quizzes at all, or none this shallow).
func draw(region: String) -> Dictionary:
	var cap: int = QuizBank.max_difficulty(region)
	var entry: Dictionary = _pick(region, cap, true)
	if entry.is_empty():
		# Every eligible question has been asked this session — start the
		# rotation over rather than going silent mid-fight.
		_asked.clear()
		entry = _pick(region, cap, false)
	if entry.is_empty():
		return {}
	var id: String = str(entry.get("id", ""))
	_asked[id] = true
	_last_id = id
	return entry


## How many questions this region+progress can currently reach. Used for the
## boot log so an empty bank is obvious before a player hits it.
func eligible_count(region: String) -> int:
	var cap: int = QuizBank.max_difficulty(region)
	var n: int = 0
	for entry: Dictionary in ContentDB.get_all("quizzes"):
		if QuizBank.is_usable(entry, cap):
			n += 1
	return n


func forget_session() -> void:
	_asked.clear()
	_last_id = ""


## The hardest difficulty the campaign has unlocked (WORLDBOOK Part III gate).
static func max_difficulty(region: String) -> int:
	var cleared: int = QuizBank.shrines_cleared()
	var cap: int = BASE_MAX_DIFFICULTY
	if cleared >= SHRINES_FOR_D3:
		cap = 3
	if cleared >= SHRINES_FOR_D4:
		cap = 4
	# D5 is endgame material: every shrine walked, or the Citadel itself once
	# the run is far enough along that its exterior isn't an early detour.
	if cleared >= SHRINE_FLAGS.size() or (region == ENDGAME_REGION and cleared >= SHRINES_FOR_D4):
		cap = TOP_DIFFICULTY
	return cap


static func shrines_cleared() -> int:
	var n: int = 0
	for flag: String in SHRINE_FLAGS:
		if GameState.has_flag(flag):
			n += 1
	return n


## A record is only usable if it can actually be presented AND answered.
static func is_usable(entry: Dictionary, max_diff: int) -> bool:
	if str(entry.get("id", "")).is_empty():
		return false
	if str(entry.get("question", "")).is_empty():
		return false
	var choices: Array = entry.get("choices", [])
	if choices.size() != CHOICE_COUNT:
		return false
	for choice: Variant in choices:
		if str(choice).is_empty():
			return false
	var answer: int = int(entry.get("answer_index", -1))
	if answer < 0 or answer >= CHOICE_COUNT:
		return false
	return int(entry.get("difficulty", 1)) <= max_diff


func _pick(region: String, cap: int, skip_asked: bool) -> Dictionary:
	var topics: Array = REGION_TOPICS.get(region, [])
	var preferred: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	var held_back: Dictionary = {}
	for entry: Dictionary in ContentDB.get_all("quizzes"):
		if not QuizBank.is_usable(entry, cap):
			continue
		var id: String = str(entry.get("id", ""))
		if skip_asked and _asked.has(id):
			continue
		if id == _last_id:
			held_back = entry  # never twice running — unless it's all we have
			continue
		if topics.is_empty() or topics.has(str(entry.get("topic", ""))):
			preferred.append(entry)
		else:
			rest.append(entry)
	if preferred.is_empty() and rest.is_empty():
		# Only a bank of one can end up here, and only on the final pass.
		return held_back if not skip_asked else {}
	if preferred.is_empty():
		return rest[randi() % rest.size()]
	if rest.is_empty() or randf() < PREFERRED_CHANCE:
		return preferred[randi() % preferred.size()]
	return rest[randi() % rest.size()]
