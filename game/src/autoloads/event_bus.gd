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
## Combat charge meter (0..1). Combat v1 owns the meter and the special that
## spends it; the knowledge channel (milestone 7) feeds it from in-combat quizzes.
signal knowledge_charge_changed(fraction: float)
## The knowledge channel — Kern and Bit combining power through questions
## (milestone 7). PlayerCombat requests it (special pressed, meter part-full);
## KnowledgePrompt opens and owns the card, then reports how it closed.
## completed=true means the meter filled and the combined strike fires.
signal knowledge_channel_requested()
signal knowledge_channel_started()
signal knowledge_channel_ended(completed: bool)

# Combat
## An enemy came apart. monster_id is "" for non-content sparring rigs.
signal enemy_defeated(monster_id: String, position: Vector3)
signal enemy_hit(monster_id: String, remaining_hearts: float)
## Kern's life pool changed / he took a blow / he was downed and reformed.
signal player_hearts_changed(current: float, max_hearts: float)
signal player_hit(amount: float)
signal player_reformed()
## Screen-shake request, 0..1 trauma. CameraRig listens and decays it.
signal combat_shake(amount: float)

# Companion (Bit) & discovery
signal bit_spoke(line: String, kind: String)
signal landmark_named(landmark_id: String, display_name: String)
