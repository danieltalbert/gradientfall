extends Node
## GameState — session-lived game state, the single source of truth for
## everything a save file will serialize.
##
## Save/load itself lands in a later Phase 1 milestone; this autoload already
## carries the versioned shape so systems built in between target it from day
## one. Any change to the serialized structure bumps SAVE_VERSION and adds a
## migration (CLAUDE.md iron rule 5).

const SAVE_VERSION: int = 1

var player_name: String = "Kern"
var current_region: String = "datasedge_meadows"
var tokens: int = 0
var hearts_max: int = 3
## String flag id -> bool. Quest and world-state flags.
var flags: Dictionary = {}
## item_id -> count.
var inventory: Dictionary = {}


func reset() -> void:
	player_name = "Kern"
	current_region = "datasedge_meadows"
	tokens = 0
	hearts_max = 3
	flags = {}
	inventory = {}


func add_tokens(amount: int) -> void:
	tokens = maxi(0, tokens + amount)
	EventBus.tokens_changed.emit(tokens)


func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	EventBus.item_acquired.emit(item_id, count)


func set_flag(flag_id: String, value: bool = true) -> void:
	flags[flag_id] = value


func has_flag(flag_id: String) -> bool:
	return bool(flags.get(flag_id, false))


func to_save_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"player_name": player_name,
		"current_region": current_region,
		"tokens": tokens,
		"hearts_max": hearts_max,
		"flags": flags.duplicate(true),
		"inventory": inventory.duplicate(true),
	}
