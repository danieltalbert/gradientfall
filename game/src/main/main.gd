extends Node3D
## Boot scene for the vertical slice. Proves the scaffold: autoloads up,
## content database readable, scene tree renders. Replaced by the real
## Datasedge Meadows scene as Phase 1 progresses.


func _ready() -> void:
	print("Neural Quest: Gradientfall — scaffold boot OK.")
	print("GameState: save_version=%d, region=%s, player=%s" % [
		GameState.SAVE_VERSION, GameState.current_region, GameState.player_name,
	])
	var errors: PackedStringArray = ContentDB.get_load_errors()
	if errors.is_empty():
		print("ContentDB check: %d NPCs, %d quests, %d quizzes approved." % [
			ContentDB.get_all("npcs").size(),
			ContentDB.get_all("quests").size(),
			ContentDB.get_all("quizzes").size(),
		])
	else:
		push_error("ContentDB reported %d load error(s) — see above." % errors.size())
