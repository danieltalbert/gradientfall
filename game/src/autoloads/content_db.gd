extends Node
## ContentDB — read-only, id-indexed database of all approved game content.
##
## Content lives OUTSIDE the Godot project at ../content/approved/ (repo level)
## so the validator and external generators never touch res://. Editor and
## desktop debug runs resolve that folder from the project root at boot.
## TODO (Phase 1, save/load milestone): decide export packing — likely an
## export plugin that copies approved/ into the PCK as res://content/.

const CONTENT_ROOT_RELATIVE: String = "../content/approved"

## type dir name -> required id prefix (CLAUDE.md conventions).
const CONTENT_TYPES: Dictionary = {
	"quests": "q_",
	"npcs": "npc_",
	"items": "item_",
	"monsters": "mon_",
	"quizzes": "quiz_",
	"lore": "lore_",
	"pois": "poi_",
}

## type name -> { id -> entry Dictionary }
var _db: Dictionary = {}
var _load_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


## Drops and re-reads everything from disk. Cheap at current content scale.
func reload() -> void:
	_db.clear()
	_load_errors.clear()
	var root: String = _content_root()
	for type_name: String in CONTENT_TYPES:
		_db[type_name] = {}
		_load_type(type_name, root.path_join(type_name))
	var total: int = 0
	for type_name: String in _db:
		total += (_db[type_name] as Dictionary).size()
	if _load_errors.is_empty():
		print("ContentDB: loaded %d entries across %d types from %s" % [total, _db.size(), root])
	else:
		for err: String in _load_errors:
			push_error("ContentDB: " + err)


func has_entry(type_name: String, id: String) -> bool:
	return (_db.get(type_name, {}) as Dictionary).has(id)


## Returns the entry Dictionary, or an empty Dictionary if missing.
func get_entry(type_name: String, id: String) -> Dictionary:
	var bucket: Dictionary = _db.get(type_name, {})
	return bucket.get(id, {})


func get_all(type_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in (_db.get(type_name, {}) as Dictionary).values():
		out.append(entry as Dictionary)
	return out


func get_ids(type_name: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in (_db.get(type_name, {}) as Dictionary).keys():
		out.append(id)
	return out


func get_load_errors() -> PackedStringArray:
	return _load_errors.duplicate()


func _content_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join(CONTENT_ROOT_RELATIVE).simplify_path()


func _load_type(type_name: String, dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		_load_errors.append("missing content dir: " + dir_path)
		return
	for file_name: String in dir.get_files():
		if file_name.ends_with(".json"):
			_load_file(type_name, dir_path.path_join(file_name))


func _load_file(type_name: String, path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		_load_errors.append("unreadable or empty file: " + path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Array):
		_load_errors.append("not a JSON array: " + path)
		return
	var prefix: String = CONTENT_TYPES[type_name]
	for raw: Variant in (parsed as Array):
		if not (raw is Dictionary):
			_load_errors.append("non-object entry in " + path)
			continue
		var entry: Dictionary = raw as Dictionary
		var id: String = str(entry.get("id", ""))
		if id.is_empty() or not id.begins_with(prefix):
			_load_errors.append("bad or missing id '%s' in %s" % [id, path])
			continue
		if (_db[type_name] as Dictionary).has(id):
			_load_errors.append("duplicate id '%s' in %s" % [id, path])
			continue
		(_db[type_name] as Dictionary)[id] = entry
