extends Node
## EventBus — global signal hub. The only sanctioned cross-system channel.
##
## Systems emit here and never call each other directly. Signals are added as
## the systems that emit them land; declaring the near-term set up front keeps
## signatures stable for consumers.

# World / regions
signal region_entered(region_id: String)

# Player lifecycle
signal player_spawned(player: Node3D)
signal player_died()

# Quests
signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)

# Inventory & economy
signal item_acquired(item_id: String, count: int)
signal tokens_changed(new_total: int)

# Knowledge charge / quizzes
signal quiz_answered(quiz_id: String, correct: bool)
